`timescale 1ns / 1ps
// Folded (compressed) global history, updated incrementally in O(1) per branch.
// Keeps fold = XOR over i < HIST_LEN of ghr[i] << (i % FOLD_W),  ghr[0] = newest.
// Each update: rotate left by 1, insert the new outcome at bit 0, and cancel the bit
// that just fell out of the HIST_LEN window (it lands at HIST_LEN % FOLD_W).
module folded_history #(
  parameter int HIST_LEN = 16,
  parameter int FOLD_W   = 9
)(
  input  logic              clk,
  input  logic              rst,
  input  logic              update_i,
  input  logic              new_bit_i,   // outcome being shifted in
  input  logic              old_bit_i,   // ghr[HIST_LEN-1] before the shift
  output logic [FOLD_W-1:0] fold_o
);

  localparam int OUTPOINT = HIST_LEN % FOLD_W;

  logic [FOLD_W-1:0] fold_q;
  logic [FOLD_W:0]   t;
  logic [FOLD_W-1:0] fold_nxt;

  always_comb begin
    t = {fold_q, new_bit_i};
    t[OUTPOINT] = t[OUTPOINT] ^ old_bit_i;
    fold_nxt = t[FOLD_W-1:0];
    fold_nxt[0] = fold_nxt[0] ^ t[FOLD_W];
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst)           fold_q <= '0;
    else if (update_i) fold_q <= fold_nxt;
  end

  assign fold_o = fold_q;

endmodule
