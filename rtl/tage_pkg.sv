`timescale 1ns / 1ps
package tage_pkg;

  localparam int PC_W       = 32;
  localparam int NUM_TABLES = 6;              // tagged components T1..T6
  localparam int TID_W      = 3;              // 0 = bimodal, 1..6 = tagged

  // Base predictor: 4096 x 2-bit counters = 8 Kbit
  localparam int BIM_IDX_W  = 12;
  localparam int BIM_CTR_W  = 2;

  // Tagged tables: 512 entries each = {tag, 3b ctr} in SRAM + 2b useful in flops
  localparam int T_IDX_W    = 9;
  localparam int CTR_W      = 3;
  localparam int U_W        = 2;
  localparam int MAX_TAG_W  = 11;

  // Geometric history lengths and tag widths, T1 (short) .. T6 (long)
  function automatic int hist_len(input int t);   // t = 0..5 for T1..T6
    case (t)
      0: return 4;
      1: return 8;
      2: return 16;
      3: return 32;
      4: return 64;
      default: return 128;
    endcase
  endfunction

  function automatic int tag_wid(input int t);
    case (t)
      0, 1: return 9;
      2, 3: return 10;
      default: return 11;
    endcase
  endfunction
  localparam int GHR_W      = 128;

  // Storage: 8192 + 512*(14+14+15+15+16+16) = 54,272 bits (~53 Kbit, inside 64 Kbit)

  // Metadata carried with each branch from predict to update
  typedef struct packed {
    logic [NUM_TABLES-1:0]                hit;        // which tables tag-matched
    logic [NUM_TABLES-1:0][T_IDX_W-1:0]   idx;
    logic [NUM_TABLES-1:0][MAX_TAG_W-1:0] tag;
    logic [NUM_TABLES-1:0][CTR_W-1:0]     ctr;
    logic [NUM_TABLES-1:0][U_W-1:0]       u;
    logic [BIM_IDX_W-1:0]                 bim_idx;
    logic [BIM_CTR_W-1:0]                 bim_ctr;
    logic [TID_W-1:0]                     prov;       // provider table (0 = bimodal)
    logic [TID_W-1:0]                     alt;        // alternate table (0 = bimodal)
    logic                                 prov_pred;
    logic                                 alt_pred;
    logic                                 weak_new;   // provider is weak and u == 0
    logic                                 final_pred;
  } tage_meta_t;

endpackage
