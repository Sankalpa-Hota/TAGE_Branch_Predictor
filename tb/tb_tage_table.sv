`timescale 1ns / 1ps
// Tagged table with TAG_W = 9; folded histories are driven straight from the file.
// Reads tests/table_ops.txt:
//   W <idx> <tag> <ctr>                                  write entry
//   U <idx> <u>                                          write useful bits
//   D <msb>                                              decay one u bit-plane
//   L <pc> <fidx> <ft1> <ft2> <idx> <tag> <hit> <ctr> <u> lookup, check hash + hit + fields
module tb_tage_table;
  import tage_pkg::*;

  localparam int TW = 9;

  logic clk = 0, rst;
  logic rd_en_i, wr_en_i, u_wr_en_i, decay_i, decay_msb_i, hit_o;
  logic [PC_W-1:0] pc_i;
  logic [T_IDX_W-1:0] fold_idx_i, idx_o, wr_idx_i, u_wr_idx_i;
  logic [TW-1:0] fold_tag1_i, tag_o, wr_tag_i;
  logic [TW-2:0] fold_tag2_i;
  logic [CTR_W-1:0] ctr_o, wr_ctr_i;
  logic [U_W-1:0] u_o, u_wr_i;

  tage_table #(.TAG_W(TW), .IDX_W(T_IDX_W)) dut (.*);

  always #5 clk = ~clk;

  int fd, n, errors, lookups, hits;
  string op;
  logic [31:0] v [9];

  initial begin
    rst = 1; rd_en_i = 0; wr_en_i = 0; u_wr_en_i = 0; decay_i = 0; decay_msb_i = 0;
    pc_i = '0; fold_idx_i = '0; fold_tag1_i = '0; fold_tag2_i = '0;
    wr_idx_i = '0; wr_tag_i = '0; wr_ctr_i = '0; u_wr_idx_i = '0; u_wr_i = '0;
    repeat (2) @(negedge clk);
    rst = 0;
    fd = $fopen("tests/table_ops.txt", "r");
    if (fd == 0) $fatal(1, "cannot open tests/table_ops.txt");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s", op);
      if (n != 1) continue;
      @(negedge clk);
      if (op == "W") begin
        n = $fscanf(fd, "%h %h %h\n", v[0], v[1], v[2]);
        wr_en_i = 1; wr_idx_i = v[0][8:0]; wr_tag_i = v[1][TW-1:0]; wr_ctr_i = v[2][2:0];
        @(negedge clk);
        wr_en_i = 0;
      end else if (op == "U") begin
        n = $fscanf(fd, "%h %h\n", v[0], v[1]);
        u_wr_en_i = 1; u_wr_idx_i = v[0][8:0]; u_wr_i = v[1][1:0];
        @(negedge clk);
        u_wr_en_i = 0;
      end else if (op == "D") begin
        n = $fscanf(fd, "%h\n", v[0]);
        decay_i = 1; decay_msb_i = v[0][0];
        @(negedge clk);
        decay_i = 0;
      end else begin
        n = $fscanf(fd, "%h %h %h %h %h %h %h %h %h\n", v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]);
        rd_en_i = 1; pc_i = v[0]; fold_idx_i = v[1][8:0]; fold_tag1_i = v[2][TW-1:0]; fold_tag2_i = v[3][TW-2:0];
        @(negedge clk);
        rd_en_i = 0;
        lookups++;
        if (hit_o) hits++;
        if (idx_o !== v[4][8:0] || tag_o !== v[5][TW-1:0] || hit_o !== v[6][0] ||
            (v[6][0] && ctr_o !== v[7][2:0]) || u_o !== v[8][1:0]) begin
          $error("pc %h: idx %h tag %h hit %b ctr %0d u %0d | expected %h %h %0d %0d %0d",
                 v[0], idx_o, tag_o, hit_o, ctr_o, u_o, v[4], v[5], v[6], v[7], v[8]);
          errors++;
        end
      end
    end
    $fclose(fd);
    if (errors == 0) $display("PASS tb_tage_table (%0d lookups, %0d hits)", lookups, hits);
    else $display("FAIL tb_tage_table (%0d errors)", errors);
    $finish;
  end
endmodule
