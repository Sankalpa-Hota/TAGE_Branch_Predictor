`timescale 1ns / 1ps
// Full TAGE testbench. Reads tests/branch_trace.txt: <pc> <taken> <class>
//   class 0 = learnable (loops, periodic patterns, a ^ b correlation), 1 = random by design.
// Each branch: predict -> read prediction + metadata -> update with the real outcome.
// A plain bimodal predictor (same size and indexing as T0) runs alongside as the baseline.
// Pass: no X on the prediction, TAGE beats bimodal, and >= 95% accuracy on learnable
// branches over the second half of the trace (after warm-up).
module tb_tage_top;
  import tage_pkg::*;

  logic clk = 0, rst;
  logic pred_valid_i, pred_ready_o, resp_valid_o, resp_taken_o;
  logic [PC_W-1:0] pred_pc_i, resp_pc_o;
  tage_meta_t resp_meta_o, upd_meta_i;
  logic upd_valid_i, upd_taken_i;

  tage_top #(.U_RESET_LOG(13)) dut (.*);

  always #5 clk = ~clk;

  logic [1:0] bim_ref [4096];

  int fd, n, total, half;
  int tage_miss, bim_miss, det_n2, det_ok2, rnd_n, rnd_ok, errors, decays;
  int prov_hist [NUM_TABLES + 1];
  logic [31:0] pc, tk, cls;
  logic [11:0] bi;
  logic tage_pred, bim_pred;

  always @(posedge clk) if (dut.decay) decays++;

  initial begin
    rst = 1; pred_valid_i = 0; pred_pc_i = '0; upd_valid_i = 0; upd_taken_i = 0; upd_meta_i = '0;
    for (int i = 0; i < 4096; i++) bim_ref[i] = 2'b01;
    for (int i = 0; i <= NUM_TABLES; i++) prov_hist[i] = 0;

    fd = $fopen("tests/branch_trace.txt", "r");
    if (fd == 0) $fatal(1, "cannot open tests/branch_trace.txt");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%h %h %h\n", pc, tk, cls);
      if (n == 3) total++;
    end
    $fclose(fd);
    half = total / 2;

    repeat (3) @(negedge clk);
    rst = 0;
    while (!pred_ready_o) @(negedge clk);

    fd = $fopen("tests/branch_trace.txt", "r");
    for (int k = 0; k < total; k++) begin
      n = $fscanf(fd, "%h %h %h\n", pc, tk, cls);

      // predict
      pred_valid_i = 1; pred_pc_i = pc;
      @(negedge clk);
      pred_valid_i = 0;
      if (!resp_valid_o || resp_pc_o !== pc || $isunknown(resp_taken_o)) begin
        $error("branch %0d: bad response valid=%b pc=%h taken=%b", k, resp_valid_o, resp_pc_o, resp_taken_o);
        errors++;
      end
      tage_pred = resp_taken_o;
      prov_hist[resp_meta_o.prov]++;

      // baseline
      bi = pc[13:2];
      bim_pred = bim_ref[bi][1];
      if (tk[0]) bim_ref[bi] = (bim_ref[bi] == 2'b11) ? 2'b11 : bim_ref[bi] + 1'b1;
      else       bim_ref[bi] = (bim_ref[bi] == 2'b00) ? 2'b00 : bim_ref[bi] - 1'b1;

      if (tage_pred != tk[0]) tage_miss++;
      if (bim_pred != tk[0]) bim_miss++;
      if (k >= half) begin
        if (cls == 0) begin det_n2++; if (tage_pred == tk[0]) det_ok2++; end
        else          begin rnd_n++;  if (tage_pred == tk[0]) rnd_ok++;  end
      end

      // update
      upd_valid_i = 1; upd_taken_i = tk[0]; upd_meta_i = resp_meta_o;
      @(negedge clk);
      upd_valid_i = 0;
    end
    $fclose(fd);

    $display("branches %0d", total);
    $display("TAGE    mispredicts %0d (%0.2f per 1K branches)", tage_miss, 1000.0 * real'(tage_miss) / real'(total));
    $display("bimodal mispredicts %0d (%0.2f per 1K branches)", bim_miss, 1000.0 * real'(bim_miss) / real'(total));
    $display("2nd half: learnable %0.2f%% correct (%0d), random %0.2f%% (%0d)",
             100.0 * real'(det_ok2) / real'(det_n2), det_n2, 100.0 * real'(rnd_ok) / real'(rnd_n), rnd_n);
    $display("provider: bimodal %0d | T1 %0d T2 %0d T3 %0d T4 %0d T5 %0d T6 %0d | u decays %0d",
             prov_hist[0], prov_hist[1], prov_hist[2], prov_hist[3], prov_hist[4], prov_hist[5], prov_hist[6], decays);

    if (tage_miss >= bim_miss) begin $error("TAGE did not beat bimodal"); errors++; end
    if (real'(det_ok2) < 0.95 * real'(det_n2)) begin $error("learnable accuracy below 95%%"); errors++; end
    if (errors == 0) $display("PASS tb_tage_top");
    else $display("FAIL tb_tage_top (%0d errors)", errors);
    $finish;
  end
endmodule
