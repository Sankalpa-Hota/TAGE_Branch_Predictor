`timescale 1ns / 1ps
// Two-port SRAM macro model: one read port + one write port per cycle.
// Read data is registered (1-cycle latency) and holds until the next read.
// Same-address read and write in one cycle returns the OLD data (read-first).
module sram_1r1w #(
  parameter int DEPTH = 512,
  parameter int WIDTH = 16
)(
  input  logic                     clk,

  input  logic                     rd_en_i,
  input  logic [$clog2(DEPTH)-1:0] rd_addr_i,
  output logic [WIDTH-1:0]         rd_data_o,

  input  logic                     wr_en_i,
  input  logic [$clog2(DEPTH)-1:0] wr_addr_i,
  input  logic [WIDTH-1:0]         wr_data_i
);

  logic [WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge clk) begin
    if (rd_en_i) rd_data_o <= mem[rd_addr_i];
    if (wr_en_i) mem[wr_addr_i] <= wr_data_i;
  end

endmodule
