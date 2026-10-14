`timescale 1ns / 1ps
// Reads tests/sram_ops.txt:
//   W <addr> <data> 0       write
//   R <addr> 0 <expected>   read
//   B <addr> <data> <old>   read + write same address in one cycle -> expect old data
module tb_sram_1r1w;
  localparam int DEPTH = 64;
  localparam int WIDTH = 16;

  logic clk = 0;
  logic rd_en_i, wr_en_i;
  logic [$clog2(DEPTH)-1:0] rd_addr_i, wr_addr_i;
  logic [WIDTH-1:0] rd_data_o, wr_data_i;

  sram_1r1w #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (.*);

  always #5 clk = ~clk;

  int fd, n, errors, reads;
  string op;
  logic [31:0] a, d, e;

  initial begin
    rd_en_i = 0; wr_en_i = 0; rd_addr_i = '0; wr_addr_i = '0; wr_data_i = '0;
    fd = $fopen("tests/sram_ops.txt", "r");
    if (fd == 0) $fatal(1, "cannot open tests/sram_ops.txt");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s %h %h %h\n", op, a, d, e);
      if (n != 4) continue;
      @(negedge clk);
      rd_en_i = (op != "W"); rd_addr_i = a[5:0];
      wr_en_i = (op != "R"); wr_addr_i = a[5:0]; wr_data_i = d[WIDTH-1:0];
      @(negedge clk);
      rd_en_i = 0; wr_en_i = 0;
      if (op != "W") begin
        reads++;
        if (rd_data_o !== e[WIDTH-1:0]) begin
          $error("%s addr %0h: got %h expected %h", op, a, rd_data_o, e[WIDTH-1:0]);
          errors++;
        end
      end
    end
    $fclose(fd);
    if (errors == 0) $display("PASS tb_sram_1r1w (%0d reads checked)", reads);
    else $display("FAIL tb_sram_1r1w (%0d errors)", errors);
    $finish;
  end
endmodule
