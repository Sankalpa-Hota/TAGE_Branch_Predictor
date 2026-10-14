`timescale 1ns / 1ps
// Base predictor T0: 4096 x 2-bit saturating counters indexed by PC.
// Gives the prediction when no tagged table hits, and is the fallback "alt" prediction.
module tage_bimodal
  import tage_pkg::*;
(
  input  logic                 clk,

  // Stage 0 read, stage 1 result
  input  logic                 rd_en_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [PC_W-1:0]      pc_i,      // only PC[13:2] indexes the table
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [BIM_IDX_W-1:0] idx_o,
  output logic [BIM_CTR_W-1:0] ctr_o,

  // Update / init write
  input  logic                 wr_en_i,
  input  logic [BIM_IDX_W-1:0] wr_idx_i,
  input  logic [BIM_CTR_W-1:0] wr_ctr_i
);

  logic [BIM_IDX_W-1:0] rd_idx;

  assign rd_idx = pc_i[2 +: BIM_IDX_W];

  sram_1r1w #(.DEPTH(1 << BIM_IDX_W), .WIDTH(BIM_CTR_W)) u_bim_sram (
    .clk       (clk),
    .rd_en_i   (rd_en_i),
    .rd_addr_i (rd_idx),
    .rd_data_o (ctr_o),
    .wr_en_i   (wr_en_i),
    .wr_addr_i (wr_idx_i),
    .wr_data_i (wr_ctr_i)
  );

  always_ff @(posedge clk) if (rd_en_i) idx_o <= rd_idx;

endmodule
