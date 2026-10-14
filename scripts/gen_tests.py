#!/usr/bin/env python3
"""Generate the .txt stimulus/expected files used by the testbenches in tb/.

Usage: python3 scripts/gen_tests.py [seed]
"""
import os
import random
import sys

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 1
random.seed(SEED)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests")
os.makedirs(OUT, exist_ok=True)


def write(name, lines):
    with open(os.path.join(OUT, name), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{name}: {len(lines)} lines")


# ---------------------------------------------------------------- sram_1r1w
def gen_sram():
    depth, mem, lines = 64, {}, []
    for _ in range(500):
        a = random.randrange(depth)
        r = random.random()
        if r < 0.4 or a not in mem:
            d = random.getrandbits(16)
            mem[a] = d
            lines.append(f"W {a:x} {d:04x} 0")
        elif r < 0.75:
            lines.append(f"R {a:x} 0 {mem[a]:04x}")
        else:  # read and write the same address in one cycle -> old data
            d = random.getrandbits(16)
            lines.append(f"B {a:x} {d:04x} {mem[a]:04x}")
            mem[a] = d
    write("sram_ops.txt", lines)


# ---------------------------------------------------------------- folded history
def gen_fold():
    bits = []
    for i in range(3000):
        if i % 500 < 100:
            bits.append(1)                     # long taken runs
        elif i % 7 == 0:
            bits.append(0)
        else:
            bits.append(random.getrandbits(1))
    write("fold_bits.txt", [str(b) for b in bits])


# ---------------------------------------------------------------- bimodal
def gen_bimodal():
    ctr, lines = {}, []
    idxs = [random.randrange(4096) for _ in range(20)]
    for _ in range(1500):
        i = random.choice(idxs)
        c = ctr.get(i, 1)                      # init sweep writes weak not-taken (01)
        if random.random() < 0.6:
            t = 1 if random.random() < 0.7 else 0
            # TB reads the counter first (metadata), then updates it
            lines.append(f"U {i:x} {t} {c}")
            ctr[i] = min(c + 1, 3) if t else max(c - 1, 0)
        else:
            lines.append(f"P {i:x} 0 {c}")
    write("bimodal_ops.txt", lines)


# ---------------------------------------------------------------- tagged table (TAG_W = 9)
def table_hash(pc, fidx, ft1, ft2, tw=9):
    pcw = pc >> 2
    idx = (pcw & 0x1FF) ^ ((pcw >> 9) & 0x1FF) ^ fidx
    tag = ((pcw >> 9) & ((1 << tw) - 1)) ^ ft1 ^ ((ft2 << 1) & ((1 << tw) - 1))
    return idx & 0x1FF, tag


def gen_table():
    entries, u, lines = {i: (0, 0) for i in range(512)}, {}, []
    branches = []
    for _ in range(24):
        branches.append((random.getrandbits(32) & ~3, random.getrandbits(9),
                         random.getrandbits(9), random.getrandbits(8)))
    for k in range(900):
        pc, fi, f1, f2 = random.choice(branches)
        idx, tag = table_hash(pc, fi, f1, f2)
        r = random.random()
        if k in (400, 700):
            msb = 1 if k == 400 else 0
            lines.append(f"D {msb}")
            for i in u:
                u[i] &= 0b01 if msb else 0b10
        elif r < 0.3:
            c = random.randrange(8)
            entries[idx] = (tag, c)
            lines.append(f"W {idx:x} {tag:x} {c}")
        elif r < 0.45:
            v = random.randrange(4)
            u[idx] = v
            lines.append(f"U {idx:x} {v}")
        else:
            e = entries.get(idx)
            hit = 1 if e and e[0] == tag else 0
            c = e[1] if e else 0
            lines.append(f"L {pc:08x} {fi:x} {f1:x} {f2:x} {idx:x} {tag:x} {hit} {c} {u.get(idx, 0)}")
    # first write every index the test touches so lookups never read X
    init = [f"W {i:x} 0 0" for i in range(512)]
    write("table_ops.txt", init + lines)


# ---------------------------------------------------------------- branch trace
def gen_trace():
    """Program-like trace. class 0 = deterministic (learnable), 1 = random by design."""
    lines = []
    pcs = {n: 0x8000_0000 + 0x40 * i + 4 * random.randrange(16) for i, n in enumerate(
        ["loop12", "alt", "p5", "rand_a", "rand_b", "xor_ab", "always", "loop33", "noise", "p3"])}
    p5 = [1, 1, 0, 1, 0]
    p3 = [1, 0, 0]
    k5 = k3 = alt = 0
    for _ in range(1400):
        a = random.getrandbits(1)
        b = random.getrandbits(1)
        lines.append(f"{pcs['rand_a']:08x} {a} 1")
        lines.append(f"{pcs['rand_b']:08x} {b} 1")
        lines.append(f"{pcs['xor_ab']:08x} {a ^ b} 0")
        for i in range(12):                                   # loop with fixed trip count
            lines.append(f"{pcs['loop12']:08x} {1 if i < 11 else 0} 0")
            if i % 3 == 0:
                lines.append(f"{pcs['alt']:08x} {alt} 0")
                alt ^= 1
        lines.append(f"{pcs['p5']:08x} {p5[k5]} 0")
        k5 = (k5 + 1) % 5
        lines.append(f"{pcs['p3']:08x} {p3[k3]} 0")
        k3 = (k3 + 1) % 3
        lines.append(f"{pcs['always']:08x} 1 0")
        if random.random() < 0.15:
            lines.append(f"{pcs['noise']:08x} {random.getrandbits(1)} 1")
    write("branch_trace.txt", lines)


if __name__ == "__main__":
    gen_sram()
    gen_fold()
    gen_bimodal()
    gen_table()
    gen_trace()
