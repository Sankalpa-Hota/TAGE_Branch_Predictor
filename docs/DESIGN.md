# TAGE Branch Predictor: Design Document

## 1. Spec at a glance

| Item | Value |
|---|---|
| Algorithm | TAGE (TAgged GEometric history length), Seznec & Michaud |
| Components | 1 bimodal base (T0) + 6 tagged tables (T1–T6) |
| History lengths | 4, 8, 16, 32, 64, 128 (geometric, α = 2) |
| Base table | 4096 × 2-bit counters |
| Tagged tables | 512 entries each: tag (9/9/10/10/11/11 b) + 3-bit counter + 2-bit useful |
| Storage | 8,192 + 46,080 = **54,272 bits (~53 Kbit)**, under the 64 Kbit budget |
| Global history | 128-bit shift register + 18 folded registers (3 per table) |
| Pipeline | 2 stages: hash + SRAM read → tag compare + select |
| Throughput | 1 prediction/cycle, 1 update/cycle |
| Memories | 1R1W SRAM macros, plus useful bits in flops for 1-cycle decay |

## 2. How the prediction is formed

```
            PC ──┬──────────────► T0 bimodal (PC[13:2]) ───────────────────────┐
                 │                                                             │
 GHR[127:0] ─► folds ─► hash ─► T1 (L=4)   ── tag match? ──┐                   │
                       hash ─► T2 (L=8)   ── tag match? ──┤                    │
                       hash ─► T3 (L=16)  ── tag match? ──┤   provider = longest hit
                       hash ─► T4 (L=32)  ── tag match? ──┼─► alt      = next longest hit
                       hash ─► T5 (L=64)  ── tag match? ──┤              (or T0)
                       hash ─► T6 (L=128) ── tag match? ──┘                    │
                                                                               ▼
                         weak & new provider && use_alt_on_na ? alt : provider ──► taken
```

- Short-history tables learn quickly and cover common branches. Long-history tables catch branches that only correlate with outcomes far back (long loops, deep if-chains).
- The **longest** table that hits wins, because it has seen the most specific context.
- A freshly allocated entry hasn't proven itself yet (weak counter, u = 0). A 4-bit `use_alt_on_na` counter learns whether the alternate prediction is more trustworthy in that case.

## 3. Pipeline

| Stage | Work |
|---|---|
| P0 | For each table: `idx = PC[10:2] ^ PC[19:11] ^ fold_idx`, `tag = PC[19:11+] ^ fold_tag1 ^ (fold_tag2 << 1)`. Read all 7 SRAMs in parallel. |
| P1 | 6 tag compares, priority-select provider/alt, apply `use_alt_on_na`. Output the prediction plus a **metadata** bundle. |

The metadata (`tage_meta_t`) travels with the branch down the pipeline and comes back at update time: every table's index, tag, counter and u bits, plus the provider/alt ids and their predictions. Update then never has to re-read the tables. That is the usual trick in real designs, and it keeps the SRAMs at 1R1W.

## 4. Submodules

### `tage_pkg.sv`: parameters and metadata type
Table count, widths, the history-length and tag-width schedule (as constant functions), and the packed `tage_meta_t` struct.

### `sram_1r1w.sv`: SRAM macro model
- One read port and one write port, so predict and update can both happen every cycle.
- 1-cycle registered read that holds its value. A same-address read and write returns the **old** data (read-first), which is how most 2-port macros behave.

### `folded_history.sv`: compressed history
- Hashing a 128-bit history into a 9-bit index every cycle would need a wide XOR tree. A folded register keeps the XOR-folded value up to date incrementally instead.
- Invariant: `fold = XOR over i < L of ghr[i] << (i mod W)`.
- Per update: rotate left by 1, XOR the new outcome into bit 0, then XOR out the bit leaving the window (it sits at `L mod W`). That's O(1) logic, about 3 XORs.
- Each table owns 3 of these: index (9 b), tag (TAG_W) and tag-1 (TAG_W−1). The two tag folds have different widths so their bits don't line up.

### `tage_bimodal.sv`: base predictor T0
- 4096 × 2-bit saturating counters indexed by PC[13:2].
- Gives the prediction when no tagged table hits, and acts as the fallback alternate.

### `tage_table.sv`: one tagged component
- Computes its own index/tag from the PC and its three folds.
- The SRAM holds `{tag, 3-bit counter}`. The 2-bit **useful** counters are flops, so the periodic reset can clear a whole bit-plane in one cycle.
- `decay_i` with `decay_msb_i` alternates between clearing all MSBs and all LSBs. This is the "graceful reset" that stops stale entries from being protected forever.

### `tage_top.sv`: control
- **Init sweep:** after reset it writes every SRAM entry (4096 cycles; tagged tables get tag 0 and a weak counter). `pred_ready_o` stays low until the sweep finishes, because real SRAMs power up as garbage.
- **Selection:** priority encoder for provider and alt, plus `use_alt_on_na`.
- **Update** (one write per table per cycle, by construction):

| Step | Rule |
|---|---|
| 1. Train | provider counter ± toward the outcome (bimodal if no table hit) |
| 2. Alt | if the provider is weak and new, also train the alt (T0 or a shorter table) |
| 3. Useful | if provider ≠ alt: u++ when the provider was right, u-- when wrong |
| 4. Allocate | on a mispredict (and the provider isn't T6): pick a longer table with u = 0 (the first, or the second with probability ½ via a 16-bit LFSR). New entry: tag, counter = weak toward the outcome, u = 0. If none is free, u-- on all longer tables. |
| 5. History | GHR and all 18 folds shift in the outcome |
| 6. Decay | every 2^U_RESET_LOG updates (default 2^18), clear one u bit-plane |

Write ports never conflict: alt < provider < allocated table, and each is a different table.

## 5. Interfaces

| Port group | Signals | Notes |
|---|---|---|
| Predict | `pred_valid/ready, pred_pc` → `resp_valid, resp_pc, resp_taken, resp_meta` | response 1 cycle later |
| Update | `upd_valid, upd_taken, upd_meta` | in program order, with the meta from predict time |

History is updated at resolve time. A front end with many branches in flight would add a speculative history plus a checkpoint for misprediction recovery (see limits below).

## 6. Verification

Each module has a self-checking SV testbench driven by a `.txt` file in `tests/`. The files come from `scripts/gen_tests.py`, which includes a Python reference model where one is needed.

| Testbench | Input | Checks |
|---|---|---|
| `tb_sram_1r1w` | `sram_ops.txt` | read/write and same-address read-first |
| `tb_folded_history` | `fold_bits.txt` | 7 (L, W) configs against the direct XOR-fold of a shadow GHR, every step |
| `tb_tage_bimodal` | `bimodal_ops.txt` | counter values and saturation vs. a Python model |
| `tb_tage_table` | `table_ops.txt` | index/tag hash vs. Python, hit/miss, counter, u write, MSB/LSB decay |
| `tb_tage_top` | `branch_trace.txt` | full predictor on a 31K-branch trace vs. a bimodal baseline |

The trace mixes a 12-trip loop, an alternating branch, period-3 and period-5 patterns, `c = a ^ b` correlation, an always-taken branch, and some deliberately random branches (`class 1`, which nobody can predict).

Result (Verilator 5.052 and Icarus 13 give identical numbers):

```
branches 31037
TAGE    mispredicts 2309 (74.40 per 1K branches)
bimodal mispredicts 7442 (239.78 per 1K branches)      -> 3.2x fewer mispredictions
2nd half: learnable 97.43% correct, random 52.93% (coin flip, as expected)
provider: bimodal 13179 | T1 8925 T2 1719 T3 4312 T4 2457 T5 395 T6 50 | u decays 3
PASS tb_tage_top
```

All six tagged tables end up as providers, which shows that allocation spreads across history lengths.

## 7. Known limits / next steps
- Non-speculative history: correct for in-order resolution. A real front end adds speculative GHR/fold update and restores from a checkpoint on mispredict.
- Metadata is read at predict time, so two in-flight branches that hit the same entry update from slightly stale values. This is accepted in most implementations.
- No loop predictor or statistical corrector (the "-SC-L" in TAGE-SC-L).
- No path history in the hashes.
