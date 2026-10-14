`timescale 1ns / 1ps
// Shifts tests/fold_bits.txt into a shadow GHR and checks several folded_history
// instances against the direct definition: fold = XOR of ghr[i] << (i % W), i < L.
module tb_folded_history;
  localparam int GW = 160;

  logic clk = 0, rst, update_i, new_bit_i;
  logic [GW-1:0] ghr;

  logic [8:0]  f_4_9, f_16_9, f_128_9;
  logic [9:0]  f_32_10;
  logic [10:0] f_64_11, f_128_11;
  logic [7:0]  f_8_8;

  folded_history #(.HIST_LEN(4),   .FOLD_W(9))  u0 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[3]),   .fold_o(f_4_9));
  folded_history #(.HIST_LEN(8),   .FOLD_W(8))  u1 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[7]),   .fold_o(f_8_8));
  folded_history #(.HIST_LEN(16),  .FOLD_W(9))  u2 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[15]),  .fold_o(f_16_9));
  folded_history #(.HIST_LEN(32),  .FOLD_W(10)) u3 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[31]),  .fold_o(f_32_10));
  folded_history #(.HIST_LEN(64),  .FOLD_W(11)) u4 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[63]),  .fold_o(f_64_11));
  folded_history #(.HIST_LEN(128), .FOLD_W(11)) u5 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[127]), .fold_o(f_128_11));
  folded_history #(.HIST_LEN(128), .FOLD_W(9))  u6 (.clk, .rst, .update_i, .new_bit_i, .old_bit_i(ghr[127]), .fold_o(f_128_9));

  always #5 clk = ~clk;

  function automatic logic [15:0] ref_fold(input logic [GW-1:0] h, input int l, input int w);
    logic [15:0] f;
    f = '0;
    for (int i = 0; i < l; i++) f[i % w] = f[i % w] ^ h[i];
    return f;
  endfunction

  int fd, n, errors, steps;
  logic [31:0] b;

  task automatic check(input string name, input logic [15:0] got, input int l, input int w);
    logic [15:0] exp;
    exp = ref_fold(ghr, l, w);
    if (got !== exp) begin
      $error("step %0d %s: fold %h expected %h", steps, name, got, exp);
      errors++;
    end
  endtask

  initial begin
    rst = 1; update_i = 0; new_bit_i = 0; ghr = '0;
    repeat (2) @(negedge clk);
    rst = 0;
    fd = $fopen("tests/fold_bits.txt", "r");
    if (fd == 0) $fatal(1, "cannot open tests/fold_bits.txt");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%d\n", b);
      if (n != 1) continue;
      update_i = 1; new_bit_i = b[0];
      @(posedge clk);
      #1 ghr = {ghr[GW-2:0], b[0]};
      @(negedge clk);
      update_i = 0;
      steps++;
      check("L4/W9",    16'(f_4_9),    4,   9);
      check("L8/W8",    16'(f_8_8),    8,   8);
      check("L16/W9",   16'(f_16_9),   16,  9);
      check("L32/W10",  16'(f_32_10),  32,  10);
      check("L64/W11",  16'(f_64_11),  64,  11);
      check("L128/W11", 16'(f_128_11), 128, 11);
      check("L128/W9",  16'(f_128_9),  128, 9);
    end
    $fclose(fd);
    if (errors == 0) $display("PASS tb_folded_history (%0d updates x 7 folds)", steps);
    else $display("FAIL tb_folded_history (%0d errors)", errors);
    $finish;
  end
endmodule
