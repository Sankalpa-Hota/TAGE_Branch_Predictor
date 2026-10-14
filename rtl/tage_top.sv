`timescale 1ns / 1ps
// TAGE conditional branch predictor: bimodal base + 6 tagged tables with geometric
// history lengths (4, 8, 16, 32, 64, 128). ~53 Kbit of storage.
//
// Prediction pipeline (1 branch / cycle)
//   P0 : hash PC with each table's folded history, read all 7 SRAMs in parallel
//   P1 : tag compare, provider = longest hitting table, alt = next longest (or bimodal),
//        use alt instead of a weak, newly allocated provider when use_alt_on_na says so
//
// Update (one resolved branch / cycle, in program order, using the metadata from P1)
//   - provider counter (or bimodal) trained toward the outcome
//   - useful bits trained when provider and alt disagree
//   - on a misprediction, allocate one entry in a longer table with u == 0
//     (else age the u bits of the longer tables)
//   - global history + all folded histories shift in the outcome
//   - every 2^U_RESET_LOG updates, clear one u bit-plane (MSB, then LSB)
//
// After reset an init sweep writes every SRAM entry (4096 cycles), pred_ready_o is low.
module tage_top
  import tage_pkg::*;
#(
  parameter int U_RESET_LOG = 18
)(
  input  logic        clk,
  input  logic        rst,

  // Predict
  input  logic        pred_valid_i,
  output logic        pred_ready_o,
  input  logic [PC_W-1:0] pred_pc_i,

  output logic        resp_valid_o,
  output logic [PC_W-1:0] resp_pc_o,
  output logic        resp_taken_o,
  output tage_meta_t  resp_meta_o,

  // Update with the resolved outcome
  input  logic        upd_valid_i,
  input  logic        upd_taken_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  tage_meta_t  upd_meta_i      // .hit is informational, not needed for update
  /* verilator lint_on UNUSEDSIGNAL */
);

  localparam int NT = NUM_TABLES;

  // --------------------------------------------------------
  // Init sweep
  // --------------------------------------------------------
  logic                 init_q;
  logic [BIM_IDX_W-1:0] init_cnt_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      init_q     <= 1'b1;
      init_cnt_q <= '0;
    end else if (init_q) begin
      init_cnt_q <= init_cnt_q + 1'b1;
      if (&init_cnt_q) init_q <= 1'b0;
    end
  end

  assign pred_ready_o = ~init_q;

  logic p0_fire, upd_fire;
  assign p0_fire  = pred_valid_i & pred_ready_o;
  assign upd_fire = upd_valid_i & ~init_q;

  // --------------------------------------------------------
  // Global history
  // --------------------------------------------------------
  logic [GHR_W-1:0] ghr_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst)           ghr_q <= '0;
    else if (upd_fire) ghr_q <= {ghr_q[GHR_W-2:0], upd_taken_i};
  end

  // --------------------------------------------------------
  // Table signals
  // --------------------------------------------------------
  logic [NT-1:0]                hit, t_wr_en, t_u_wr_en;
  logic [NT-1:0][CTR_W-1:0]     t_ctr, t_wr_ctr;
  logic [NT-1:0][U_W-1:0]       t_u, t_u_wr;
  logic [NT-1:0][T_IDX_W-1:0]   t_idx, t_wr_idx;
  logic [NT-1:0][MAX_TAG_W-1:0] t_tag, t_wr_tag;

  logic decay, decay_msb_q;

  for (genvar t = 0; t < NT; t++) begin : g_table
    localparam int L  = hist_len(t);
    localparam int TW = tag_wid(t);

    logic [T_IDX_W-1:0] f_idx;
    logic [TW-1:0]      f_tag1;
    logic [TW-2:0]      f_tag2;
    logic [TW-1:0]      tag_s1;

    folded_history #(.HIST_LEN(L), .FOLD_W(T_IDX_W)) u_fidx (
      .clk(clk), .rst(rst), .update_i(upd_fire), .new_bit_i(upd_taken_i),
      .old_bit_i(ghr_q[L-1]), .fold_o(f_idx));
    folded_history #(.HIST_LEN(L), .FOLD_W(TW)) u_ftag1 (
      .clk(clk), .rst(rst), .update_i(upd_fire), .new_bit_i(upd_taken_i),
      .old_bit_i(ghr_q[L-1]), .fold_o(f_tag1));
    folded_history #(.HIST_LEN(L), .FOLD_W(TW - 1)) u_ftag2 (
      .clk(clk), .rst(rst), .update_i(upd_fire), .new_bit_i(upd_taken_i),
      .old_bit_i(ghr_q[L-1]), .fold_o(f_tag2));

    tage_table #(.TAG_W(TW), .IDX_W(T_IDX_W)) u_table (
      .clk         (clk),
      .rst         (rst),
      .rd_en_i     (p0_fire),
      .pc_i        (pred_pc_i),
      .fold_idx_i  (f_idx),
      .fold_tag1_i (f_tag1),
      .fold_tag2_i (f_tag2),
      .hit_o       (hit[t]),
      .ctr_o       (t_ctr[t]),
      .u_o         (t_u[t]),
      .idx_o       (t_idx[t]),
      .tag_o       (tag_s1),
      .wr_en_i     (init_q ? (init_cnt_q < BIM_IDX_W'(1 << T_IDX_W)) : t_wr_en[t]),
      .wr_idx_i    (init_q ? init_cnt_q[T_IDX_W-1:0] : t_wr_idx[t]),
      .wr_tag_i    (init_q ? '0 : t_wr_tag[t][TW-1:0]),
      .wr_ctr_i    (init_q ? CTR_W'(3) : t_wr_ctr[t]),
      .u_wr_en_i   (t_u_wr_en[t]),
      .u_wr_idx_i  (t_wr_idx[t]),
      .u_wr_i      (t_u_wr[t]),
      .decay_i     (decay),
      .decay_msb_i (decay_msb_q)
    );

    assign t_tag[t] = MAX_TAG_W'(tag_s1);
  end

  // --------------------------------------------------------
  // Bimodal
  // --------------------------------------------------------
  logic [BIM_IDX_W-1:0] bim_idx, bim_wr_idx;
  logic [BIM_CTR_W-1:0] bim_ctr, bim_wr_ctr;
  logic                 bim_wr_en;

  tage_bimodal u_bim (
    .clk      (clk),
    .rd_en_i  (p0_fire),
    .pc_i     (pred_pc_i),
    .idx_o    (bim_idx),
    .ctr_o    (bim_ctr),
    .wr_en_i  (init_q | bim_wr_en),
    .wr_idx_i (init_q ? init_cnt_q : bim_wr_idx),
    .wr_ctr_i (init_q ? BIM_CTR_W'(1) : bim_wr_ctr)
  );

  // --------------------------------------------------------
  // P1: provider / alt selection
  // --------------------------------------------------------
  logic            p1_valid_q;
  logic [PC_W-1:0] p1_pc_q;
  logic [3:0]      use_alt_q;
  tage_meta_t      m;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      p1_valid_q <= 1'b0;
      p1_pc_q    <= '0;
    end else begin
      p1_valid_q <= p0_fire;
      if (p0_fire) p1_pc_q <= pred_pc_i;
    end
  end

  always_comb begin : p_select
    logic [TID_W-1:0] prov, alt;
    logic [CTR_W-1:0] pc_ctr, alt_ctr;
    logic [U_W-1:0]   pc_u;
    logic             prov_pred, alt_pred, weak_new;

    prov = '0;
    alt  = '0;
    for (int t = 0; t < NT; t++) begin
      if (hit[t]) begin
        alt  = prov;
        prov = TID_W'(t + 1);
      end
    end

    pc_ctr    = '0;
    alt_ctr   = '0;
    pc_u      = '0;
    prov_pred = bim_ctr[BIM_CTR_W-1];
    alt_pred  = bim_ctr[BIM_CTR_W-1];
    for (int t = 0; t < NT; t++) begin
      if (prov == TID_W'(t + 1)) begin
        pc_ctr    = t_ctr[t];
        pc_u      = t_u[t];
        prov_pred = pc_ctr[CTR_W-1];
      end
      if (alt == TID_W'(t + 1)) begin
        alt_ctr  = t_ctr[t];
        alt_pred = alt_ctr[CTR_W-1];
      end
    end

    weak_new = (prov != '0) && (pc_ctr == CTR_W'(3) || pc_ctr == CTR_W'(4)) && (pc_u == '0);

    m            = '0;
    m.hit        = hit;
    m.idx        = t_idx;
    m.tag        = t_tag;
    m.ctr        = t_ctr;
    m.u          = t_u;
    m.bim_idx    = bim_idx;
    m.bim_ctr    = bim_ctr;
    m.prov       = prov;
    m.alt        = alt;
    m.prov_pred  = prov_pred;
    m.alt_pred   = alt_pred;
    m.weak_new   = weak_new;
    m.final_pred = (weak_new && use_alt_q[3]) ? alt_pred : prov_pred;
  end

  assign resp_valid_o = p1_valid_q;
  assign resp_pc_o    = p1_pc_q;
  assign resp_taken_o = m.final_pred;
  assign resp_meta_o  = m;

  // --------------------------------------------------------
  // Update
  // --------------------------------------------------------
  function automatic logic [CTR_W-1:0] ctr_upd(input logic [CTR_W-1:0] c, input logic tkn);
    if (tkn) return (c == '1) ? c : c + 1'b1;
    else     return (c == '0) ? c : c - 1'b1;
  endfunction

  function automatic logic [BIM_CTR_W-1:0] bim_upd(input logic [BIM_CTR_W-1:0] c, input logic tkn);
    if (tkn) return (c == '1) ? c : c + 1'b1;
    else     return (c == '0) ? c : c - 1'b1;
  endfunction

  function automatic logic [U_W-1:0] u_upd(input logic [U_W-1:0] u, input logic inc);
    if (inc) return (u == '1) ? u : u + 1'b1;
    else     return (u == '0) ? u : u - 1'b1;
  endfunction

  logic [15:0] lfsr_q;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) lfsr_q <= 16'hACE1;
    else     lfsr_q <= {lfsr_q[14:0], lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
  end

  always_comb begin : p_update
    logic [NT-1:0][CTR_W-1:0] u_ctr;
    logic [NT-1:0][U_W-1:0]   u_u;
    logic [TID_W-1:0]         prov, alt;
    logic                     tkn, mispred, do_alloc, prov_pred, alt_pred, weak_new;
    logic [NT-1:0]            cand, pick;
    logic                     seen_one, took;

    u_ctr     = upd_meta_i.ctr;
    u_u       = upd_meta_i.u;
    prov      = upd_meta_i.prov;
    alt       = upd_meta_i.alt;
    prov_pred = upd_meta_i.prov_pred;
    alt_pred  = upd_meta_i.alt_pred;
    weak_new  = upd_meta_i.weak_new;
    tkn       = upd_taken_i;
    mispred   = (upd_meta_i.final_pred != tkn);

    t_wr_en    = '0;
    t_wr_idx   = upd_meta_i.idx;
    t_wr_tag   = upd_meta_i.tag;
    t_wr_ctr   = u_ctr;
    t_u_wr_en  = '0;
    t_u_wr     = u_u;
    bim_wr_en  = 1'b0;
    bim_wr_idx = upd_meta_i.bim_idx;
    bim_wr_ctr = bim_upd(upd_meta_i.bim_ctr, tkn);

    do_alloc = upd_fire && mispred && (prov != TID_W'(NT)) && !(weak_new && prov_pred == tkn);

    // Allocation candidates: tables longer than the provider with u == 0.
    // Take the first one, or with probability 1/2 the second one (spreads allocations).
    cand     = '0;
    pick     = '0;
    seen_one = 1'b0;
    took     = 1'b0;
    for (int t = 0; t < NT; t++) cand[t] = (TID_W'(t + 1) > prov) && (u_u[t] == '0);
    for (int t = 0; t < NT; t++) begin
      if (cand[t] && !took) begin
        if (!seen_one) begin
          pick[t]  = 1'b1;
          seen_one = 1'b1;
          if (!lfsr_q[0]) took = 1'b1;
        end else begin
          pick     = '0;
          pick[t]  = 1'b1;
          took     = 1'b1;
        end
      end
    end

    if (upd_fire) begin
      // 1. Provider counter (bimodal when nothing hit)
      if (prov == '0) bim_wr_en = 1'b1;

      // 2. A brand-new provider is unreliable: also train the alternate
      if (weak_new && alt == '0) bim_wr_en = 1'b1;

      for (int t = 0; t < NT; t++) begin
        if (prov == TID_W'(t + 1)) begin
          t_wr_en[t]  = 1'b1;
          t_wr_ctr[t] = ctr_upd(u_ctr[t], tkn);
          // 3. Useful bit: did the provider beat the alternate?
          if (prov_pred != alt_pred) begin
            t_u_wr_en[t] = 1'b1;
            t_u_wr[t]    = u_upd(u_u[t], prov_pred == tkn);
          end
        end
        if (weak_new && alt == TID_W'(t + 1)) begin
          t_wr_en[t]  = 1'b1;
          t_wr_ctr[t] = ctr_upd(u_ctr[t], tkn);
        end

        // 4. Allocate in a longer table on a misprediction, else age the longer tables
        if (do_alloc) begin
          if (|cand) begin
            if (pick[t]) begin
              t_wr_en[t]   = 1'b1;
              t_wr_ctr[t]  = tkn ? CTR_W'(4) : CTR_W'(3);
              t_u_wr_en[t] = 1'b1;
              t_u_wr[t]    = '0;
            end
          end else if (TID_W'(t + 1) > prov) begin
            t_u_wr_en[t] = 1'b1;
            t_u_wr[t]    = u_upd(u_u[t], 1'b0);
          end
        end
      end
    end
  end

  // --------------------------------------------------------
  // use_alt_on_na (4-bit) + periodic u decay
  // --------------------------------------------------------
  logic [U_RESET_LOG-1:0] tick_q;

  assign decay = upd_fire & (&tick_q);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      use_alt_q   <= 4'd8;
      tick_q      <= '0;
      decay_msb_q <= 1'b1;
    end else if (upd_fire) begin
      tick_q <= tick_q + 1'b1;
      if (decay) decay_msb_q <= ~decay_msb_q;
      if (upd_meta_i.weak_new && upd_meta_i.prov_pred != upd_meta_i.alt_pred) begin
        if (upd_meta_i.alt_pred == upd_taken_i) begin
          if (use_alt_q != 4'hF) use_alt_q <= use_alt_q + 1'b1;
        end else begin
          if (use_alt_q != 4'h0) use_alt_q <= use_alt_q - 1'b1;
        end
      end
    end
  end

endmodule
