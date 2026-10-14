`timescale 1ns / 1ps
// Reads tests/bimodal_ops.txt:
//   P <idx> 0 <exp_ctr>          predict-read and check the counter
//   U <idx> <taken> <exp_ctr>    read (check), then write the saturated update
module tb_tage_bimodal;
  import tage_pkg::*;

  logic clk = 0;
  logic rd_en_i, wr_en_i;
  logic [PC_W-1:0] pc_i;
  logic [BIM_IDX_W-1:0] idx_o, wr_idx_i;
  logic [BIM_CTR_W-1:0] ctr_o, wr_ctr_i;

  tage_bimodal dut (.*);

  always #5 clk = ~clk;

  int fd, n, errors, checks;
  string op;
  logic [31:0] i, t, c;
  logic [BIM_CTR_W-1:0] nxt;

  initial begin
    rd_en_i = 0; wr_en_i = 0; pc_i = '0; wr_idx_i = '0; wr_ctr_i = '0;
    for (int k = 0; k < (1 << BIM_IDX_W); k++) begin   // same as the init sweep in tage_top
      @(negedge clk);
      wr_en_i = 1; wr_idx_i = BIM_IDX_W'(k); wr_ctr_i = 2'b01;
    end
    @(negedge clk);
    wr_en_i = 0;
    fd = $fopen("tests/bimodal_ops.txt", "r");
    if (fd == 0) $fatal(1, "cannot open tests/bimodal_ops.txt");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s %h %h %h\n", op, i, t, c);
      if (n != 4) continue;
      @(negedge clk);
      rd_en_i = 1; pc_i = {18'b0, i[BIM_IDX_W-1:0], 2'b00};
      @(negedge clk);
      rd_en_i = 0;
      checks++;
      if (ctr_o !== c[1:0] || idx_o !== i[BIM_IDX_W-1:0]) begin
        $error("idx %0h: ctr %0d expected %0d", i, ctr_o, c);
        errors++;
      end
      if (op == "U") begin
        nxt = t[0] ? ((ctr_o == 2'b11) ? ctr_o : ctr_o + 1'b1) : ((ctr_o == 2'b00) ? ctr_o : ctr_o - 1'b1);
        wr_en_i = 1; wr_idx_i = idx_o; wr_ctr_i = nxt;
        @(negedge clk);
        wr_en_i = 0;
      end
    end
    $fclose(fd);
    if (errors == 0) $display("PASS tb_tage_bimodal (%0d reads checked)", checks);
    else $display("FAIL tb_tage_bimodal (%0d errors)", errors);
    $finish;
  end
endmodule
