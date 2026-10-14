`timescale 1ns / 1ps
// One tagged TAGE component.
//   index = PC[10:2] ^ PC[19:11] ^ fold_idx                (9 bits)
//   tag   = PC[2+IDX +: TAG_W] ^ fold_tag1 ^ (fold_tag2 << 1)
// Entry in SRAM: {tag, 3-bit signed counter}. Useful bits (2b) live in flops so the
// periodic "graceful reset" can clear one bit-plane of every entry in a single cycle.
module tage_table
  import tage_pkg::*;
#(
  parameter int TAG_W = 9,
  parameter int IDX_W = T_IDX_W
)(
  input  logic              clk,
  input  logic              rst,

  // Stage 0: lookup
  input  logic              rd_en_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [PC_W-1:0]   pc_i,         // PC[1:0] always 0
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [IDX_W-1:0]  fold_idx_i,
  input  logic [TAG_W-1:0]  fold_tag1_i,
  input  logic [TAG_W-2:0]  fold_tag2_i,

  // Stage 1: result
  output logic              hit_o,
  output logic [CTR_W-1:0]  ctr_o,
  output logic [U_W-1:0]    u_o,
  output logic [IDX_W-1:0]  idx_o,
  output logic [TAG_W-1:0]  tag_o,

  // Entry write (update / allocate / init)
  input  logic              wr_en_i,
  input  logic [IDX_W-1:0]  wr_idx_i,
  input  logic [TAG_W-1:0]  wr_tag_i,
  input  logic [CTR_W-1:0]  wr_ctr_i,

  // Useful-bit write and periodic decay
  input  logic              u_wr_en_i,
  input  logic [IDX_W-1:0]  u_wr_idx_i,
  input  logic [U_W-1:0]    u_wr_i,
  input  logic              decay_i,
  input  logic              decay_msb_i
);

  localparam int ENTRIES = 1 << IDX_W;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [PC_W-3:0]     pcw;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [IDX_W-1:0]    lk_idx;
  logic [TAG_W-1:0]    lk_tag;
  logic [TAG_W+CTR_W-1:0] rd_entry;
  logic [U_W-1:0]      u_q [ENTRIES];

  // --------------------------------------------------------
  // Hashing
  // --------------------------------------------------------
  assign pcw    = pc_i[PC_W-1:2];
  assign lk_idx = pcw[IDX_W-1:0] ^ pcw[2*IDX_W-1:IDX_W] ^ fold_idx_i;
  assign lk_tag = pcw[IDX_W +: TAG_W] ^ fold_tag1_i ^ {fold_tag2_i, 1'b0};

  // --------------------------------------------------------
  // Tag + counter SRAM
  // --------------------------------------------------------
  sram_1r1w #(.DEPTH(ENTRIES), .WIDTH(TAG_W + CTR_W)) u_entry_sram (
    .clk       (clk),
    .rd_en_i   (rd_en_i),
    .rd_addr_i (lk_idx),
    .rd_data_o (rd_entry),
    .wr_en_i   (wr_en_i),
    .wr_addr_i (wr_idx_i),
    .wr_data_i ({wr_tag_i, wr_ctr_i})
  );

  always_ff @(posedge clk) begin
    if (rd_en_i) begin
      idx_o <= lk_idx;
      tag_o <= lk_tag;
      u_o   <= u_q[lk_idx];
    end
  end

  assign hit_o = (rd_entry[TAG_W+CTR_W-1:CTR_W] == tag_o);
  assign ctr_o = rd_entry[CTR_W-1:0];

  // --------------------------------------------------------
  // Useful bits: write, graceful reset (MSB plane, then LSB plane)
  // --------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      for (int e = 0; e < ENTRIES; e++) u_q[e] <= '0;
    end else if (decay_i) begin
      for (int e = 0; e < ENTRIES; e++) begin
        if (decay_msb_i) u_q[e][U_W-1] <= 1'b0;
        else             u_q[e][0]     <= 1'b0;
      end
    end else if (u_wr_en_i) begin
      u_q[u_wr_idx_i] <= u_wr_i;
    end
  end

endmodule
