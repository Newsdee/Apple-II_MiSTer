// tb_v5_regress.sv
// =====================================================================
// Stage 1 (TB-B) for composite_decoder_v5a: lock-in on the synthetic
// 912-sample line + black clamp on the porch + F5-LOAD hue check.
//
// Architecture (coexist, mirrors the plan): the SAME synthetic 1-bit Apple
// VIDEO is encoded by apple_composite (which exposes the raw composite
// comp_sample); comp_sample is fed to BOTH the current decoder (inside
// apple_composite, loopback r/g/b) and composite_decoder_v5a (u_v5). This
// keeps v5 and the current path on identical input for comparison.
//
// The sync/blank fed to apple_composite is the EXACT derivation the real
// wrapper (video_pipeline) uses: hs_c = HBL & hblank_cnt in [130,198),
// vs_c = VBL & vblank_lines in [33,36).
//
// Checks (Stage 1 gate):
//   1. v5 horizontal lock: u_v5.line_len ~ 912 and hs_out pulses ~once/line.
//   2. v5 RGB non-trivial + black clamp: active-field R has contrast
//      (max-min > 20) and black near blanking (min < 40) -> clamp on porch.
//   3. PHASE_AT_SYNC_RISE: u_v5.phase at v5's sync rise is constant over 6
//      lines -> the re-anchor constant for the F5-LOAD fix (A6).
//   4. F5-LOAD hue: after a machine_ce stall + HBL source jump, the decoded
//      colour at a fixed column is unchanged (clean4 == post4). WITHOUT the
//      re-anchor this is EXPECTED TO DRIFT (the pristine v5 risk); it must
//      be clean once the re-anchor (Stage 1b) is added.
//
// KNOWN (recorded, not a gate): v5 RECOVERS sync from the waveform. It detects
// vsync by sampling sync at LONG_SYNC (114, a back-porch hpos). This core's
// encoder puts the SAME 68-sample hs pulse every line (no vsync extension),
// so v5's vs_out/vb_out CANNOT lock the 3-line VBL here -> v5's sync/blanking
// outputs stay DISCONNECTED in the coexist build (the native path supplies the
// final HS/VS/HBL_O/VBL_O). The RGB (the picture) is unaffected.
//
// Build (lint/sim toolchain; needs VERILATOR_ROOT set; run from the project
// root so the DUT ROM paths resolve):
//   --binary --timing -sv \
//     tools/tb_v5_regress.sv \
//     rtl/video/apple_composite.sv rtl/video/composite_decoder.sv \
//     rtl/video/composite_decoder_v5a.sv \
//     --Mdir tools/obj_dir_v5 -o tb_v5
// =====================================================================
`timescale 1ns/1ps
`default_nettype none
module tb_v5_regress;

  // 14.318 MHz (35 ps half period)
  reg CLK = 1'b0;
  always #35 CLK = ~CLK;

  // Geometry (matches this core: 912-cycle line, 352 HBL + 560 active).
  localparam int LINE_LEN    = 912;
  localparam int HBL_LEN     = 352;
  localparam int FIELD_LINES = 262;
  localparam int VBL_LINES   = 36;   // 33 porch + 3 vsync (real core VBL)

  reg [9:0] hcnt = 0;
  reg [8:0] lcnt = 0;
  reg [4:0] field = 0;  // 5 bits so it can reach 16 (phase 4)

  wire HBL = (hcnt < HBL_LEN);
  wire VBL = (lcnt < VBL_LINES);

  // 1-bit video: a spatial pattern while active, 0 during blanking.
  // Phase-3 colour zone: field 12, lcnt 100..199 -> hcnt[1] (subcarrier rate)
  // so the composite carries real chroma; phase-4 repeats it in field 16.
  wire color_zone  = (field == 12) && (lcnt >= 100) && (lcnt < 200) && !HBL;
  wire color_zone2 = (field == 16) && (lcnt >= 100) && (lcnt < 200) && !HBL;
  wire VIDEO = HBL ? 1'b0
                   : (color_zone || color_zone2) ? hcnt[1]
                   : (hcnt[8] ^ hcnt[2] ^ lcnt[4]);

  // machine_ce: models the savestate manager / OSD-pause machine enable.
  // Low = the timing generator holds HBL/VBL/VIDEO frozen while the 14 MHz
  // domain keeps running (the real save/load behavior).
  reg machine_ce = 1'b1;

  always @(posedge CLK) begin
    if (machine_ce) begin
      if (hcnt == LINE_LEN - 1) begin
        hcnt <= 0;
        if (lcnt == FIELD_LINES - 1) begin
          lcnt  <= 0;
          field <= field + 1;
        end else begin
          lcnt <= lcnt + 1;
        end
      end else begin
        hcnt <= hcnt + 1;
      end
    end
  end

  // ------------------------------------------------------------------
  // Sync/blank derivation - EXACT copy of video_pipeline's apple_composite
  // feed (hs_c/vs_c from hblank_cnt / vblank_lines + porch constants).
  // ------------------------------------------------------------------
  localparam [9:0] HSYNC_FRONT_PORCH = 10'd130;
  localparam [9:0] HSYNC_WIDTH       = 10'd68;
  localparam [6:0] VSYNC_FRONT_PORCH = 7'd33;
  localparam [6:0] VSYNC_LINES       = 7'd3;

  reg         hbl_d;
  wire        hbl_rise   = HBL & ~hbl_d;
  always @(posedge CLK) if (machine_ce) hbl_d <= HBL;

  reg [9:0] hblank_cnt;
  always @(posedge CLK) begin
    if (machine_ce) begin
      if (HBL) hblank_cnt <= hblank_cnt + 10'd1;
      else     hblank_cnt <= 10'd0;
    end
  end

  reg [6:0] vblank_lines;
  always @(posedge CLK) begin
    if (machine_ce) begin
      if (VBL) begin
        if (hbl_rise) vblank_lines <= vblank_lines + 7'd1;
      end else begin
        vblank_lines <= 7'd0;
      end
    end
  end

  wire hs_c = HBL & (hblank_cnt >= HSYNC_FRONT_PORCH) &
              (hblank_cnt <  HSYNC_FRONT_PORCH + HSYNC_WIDTH);
  wire vs_c = VBL & (vblank_lines >= VSYNC_FRONT_PORCH) &
              (vblank_lines <  VSYNC_FRONT_PORCH + VSYNC_LINES);

  // ------------------------------------------------------------------
  // Encoder knobs (typical color-mode; preset-0-ish).
  // ------------------------------------------------------------------
  wire        color_line   = 1'b1;   // colour on: exercises the burst
  wire [7:0]  sat          = 8'd80;
  wire [7:0]  hue          = 8'd115;
  wire [7:0]  bright       = 8'd0;
  wire [7:0]  contrast     = 8'd177;
  wire        i_mirror     = 1'b1;
  wire        chroma_short = 1'b0;
  wire [3:0]  smear        = 4'd0;
  wire [3:0]  luma_delay   = 4'd0;
  wire        agc_en       = 1'b1;
  wire        comb_en      = 1'b1;

  // Shared composite source (the raw encoder stream, Q2.21).
  wire [23:0] comp_sample;
  wire [7:0]  cur_r, cur_g, cur_b;
  apple_composite u_comp (
    .clk(CLK), .ce(machine_ce), .video(VIDEO), .pixel_delay(2'd0),
    .hs(hs_c), .vs(vs_c), .hb(HBL), .vb(VBL), .color_line(color_line),
    .sat(sat), .hue(hue), .bright(bright), .contrast(contrast),
    .i_mirror(i_mirror), .chroma_short(chroma_short), .smear(smear),
    .luma_delay(luma_delay), .agc_en(agc_en), .comb_en(comb_en),
    .r(cur_r), .g(cur_g), .b(cur_b),
    .ce_out(), .hs_out(), .vs_out(), .hb_out(), .vb_out(),
    .comp_sample(comp_sample)
  );

  // ------------------------------------------------------------------
  // v5a - fed by the SAME comp_sample. Stage 1 default knobs (Stage 3
  // remaps these to the preset table). black at blanking (0 IRE), NTSC
  // white gain, 2-line comb (exercises the linebuf prev path).
  // ------------------------------------------------------------------
  wire [7:0]  v5_sat          = 8'd128;
  wire [7:0]  v5_hue          = 8'd0;
  wire [3:0]  v5_chroma_trail = 4'd0;
  wire [3:0]  v5_sharpness    = 4'd0;
  wire [1:0]  v5_black_stretch= 2'd0;
  wire [15:0] v5_brightness   = 16'sd0;     // black at blanking (0 IRE)
  wire [15:0] v5_contrast     = 16'sd2857;  // NTSC white gain
  wire [1:0]  v5_comb_mode    = 2'd1;       // 2-line comb

  wire [7:0]  v5_r, v5_g, v5_b;
  wire        v5_ce, v5_pix, v5_hs, v5_vs, v5_hb, v5_vb;
  composite_decoder_v5a u_v5 (
    .clk(CLK), .reset(v5_reset), .ce(machine_ce), .comp(comp_sample),
    .sat(v5_sat), .hue(v5_hue), .chroma_trail(v5_chroma_trail),
    .sharpness(v5_sharpness), .black_stretch(v5_black_stretch),
    .brightness(v5_brightness), .contrast(v5_contrast), .comb_mode(v5_comb_mode),
    .ce_out(v5_ce), .pix_out(v5_pix), .hs_out(v5_hs), .vs_out(v5_vs),
    .hb_out(v5_hb), .vb_out(v5_vb), .r_out(v5_r), .g_out(v5_g), .b_out(v5_b)
  );

  // v5 synchronous reset: pulse at t=0 (models reset_cold), drop after settle.
  reg v5_reset = 1'b1;
  initial begin
    repeat (24) @(posedge CLK);
    v5_reset = 1'b0;
  end

  // v5's recovered sync leading edge (line_start) - used to sample the phase.
  wire v5_line_start = u_v5.sync_l && ~u_v5.sync_d;

  // DEBUG: log line_start events (machine hcnt + v5 hpos + comp + tip). The
  // first block is the pwrup transient (tip settling); the post-transient block
  // (field >= 2) should show ONE event per line at hcnt ~ 130 (the hs pulse).
  localparam int DBG_N = 40;
  localparam int DBG2_N = 10;
  integer dbg_n = 0, dbg2_n = 0;
  logic [9:0]  dbg_hcnt [0:DBG_N-1];
  logic [10:0] dbg_hpos [0:DBG_N-1];
  logic [23:0] dbg_comp [0:DBG_N-1];
  logic [23:0] dbg_tip  [0:DBG_N-1];
  logic [9:0]  dbg2_hcnt [0:DBG2_N-1];
  logic [10:0] dbg2_hpos [0:DBG2_N-1];
  logic [23:0] dbg2_tip  [0:DBG2_N-1];
  always @(posedge CLK) begin
    if (v5_line_start && dbg_n < DBG_N) begin
      dbg_hcnt[dbg_n] <= hcnt;
      dbg_hpos[dbg_n] <= u_v5.hpos;
      dbg_comp[dbg_n] <= comp_sample;
      dbg_tip[dbg_n]  <= u_v5.tip;
      dbg_n <= dbg_n + 1;
    end
    if (field >= 2 && v5_line_start && dbg2_n < DBG2_N) begin
      dbg2_hcnt[dbg2_n] <= hcnt;
      dbg2_hpos[dbg2_n] <= u_v5.hpos;
      dbg2_tip[dbg2_n]  <= u_v5.tip;
      dbg2_n <= dbg2_n + 1;
    end
  end

  // ------------------------------------------------------------------
  // Monitor 1: horizontal lock. line_len sampled each v5 line_start (post-
  // transient, field >= 1 so the tip has settled to the sync level); hs_out
  // rise count over the same clean window.
  // ------------------------------------------------------------------
  reg [15:0] line_len_sample [0:8];
  integer    line_len_n = 0;
  integer    hs_rises   = 0;
  reg        hs_d;
  always @(posedge CLK) begin
    if (field >= 2 && v5_line_start) begin
      if (line_len_n < 9) line_len_sample[line_len_n] <= u_v5.hpos + 11'd1;  // =line_len
      line_len_n <= line_len_n + 1;
    end
    hs_d <= v5_hs;
    if (field >= 1 && v5_hs && !hs_d) hs_rises <= hs_rises + 1;
  end

  // Monitor 2: active-field R stats (contrast + black clamp).
  integer r_min = 256, r_max = -1, r_samples = 0;
  always @(posedge CLK) begin
    if (field >= 5 && lcnt >= VBL_LINES && !v5_hb) begin
      r_samples <= r_samples + 1;
      if (int'(v5_r) < r_min) r_min <= int'(v5_r);
      if (int'(v5_r) > r_max) r_max <= int'(v5_r);
    end
  end

  // Monitor 3: PHASE_AT_SYNC_RISE - u_v5.phase at v5's line_start over 6
  // consecutive lines (the re-anchor constant; must be constant).
  reg [23:0] phase_at_sync [0:5];
  integer    phase_n = 0;
  always @(posedge CLK) begin
    if (v5_line_start && phase_n < 6) begin
      phase_at_sync[phase_n] <= u_v5.phase;
      phase_n <= phase_n + 1;
    end
  end

  // Monitor 4: F5-LOAD phase + colour capture (colour-zone column 600).
  // The hue-drift probe is v5's own free-running phase at the SAME column
  // before/after the load: a machine_ce stall + source jump offsets it on an
  // un-re-anchored design (the re-anchor forces phase=const at each line_start,
  // which re-aligns it). Pixel RGB is reported for reference only (a fixed
  // column can land on an achromatic sample and miss a rotation).
  logic [7:0]  pre_r, pre_g, pre_b, post_r, post_g, post_b;
  logic        pre_captured, post_captured;
  logic [7:0]  clean4_r, clean4_g, clean4_b, post4_r, post4_g, post4_b;
  logic [23:0] clean4_ph, post4_ph;
  logic        clean4_captured, post4_captured;
  always @(posedge CLK) begin
    if (field == 12 && lcnt == 120 && hcnt == 600) begin
      pre_r <= v5_r; pre_g <= v5_g; pre_b <= v5_b;
      pre_captured <= 1'b1;
    end
    if (field == 12 && lcnt == 180 && hcnt == 600) begin
      post_r <= v5_r; post_g <= v5_g; post_b <= v5_b;
      post_captured <= 1'b1;
    end
    if (field == 16 && lcnt == 120 && hcnt == 600) begin
      clean4_r  <= v5_r; clean4_g <= v5_g; clean4_b <= v5_b;
      clean4_ph <= u_v5.phase;
      clean4_captured <= 1'b1;
    end
    if (field == 16 && lcnt == 180 && hcnt == 600) begin
      post4_r  <= v5_r; post4_g <= v5_g; post4_b <= v5_b;
      post4_ph <= u_v5.phase;
      post4_captured <= 1'b1;
    end
  end

  // ------------------------------------------------------------------
  // Monitor 5 (scratch, lsmon): phase at LOCKED line starts only
  // (v5_line_start with u_v5.hpos == 911 = the 912-aligned edge at tb
  // hcnt ~131). Separates the steady-state grid from the power-on
  // transient spurious edges (tb hcnt 25..69) that the Check 3 monitor
  // captures. Also records tb hcnt of each edge (detects a slipped edge).
  //   plain: first 6 locked edges (fields 0-1, plain lines)
  //   z12:   field 12 colour-zone lines lcnt 100..113 (pre-stall)
  //   z16:   field 16 colour-zone lines lcnt 100..113 (pre-stall)
  // ------------------------------------------------------------------
  localparam int LSM_PLAIN_N = 6;
  localparam int LSM_ZONE_N  = 4;
  integer lsm_plain_n = 0, lsm_z12_n = 0, lsm_z16_n = 0;
  logic [23:0] lsm_plain_ph [0:LSM_PLAIN_N-1];
  logic [9:0]  lsm_plain_hcnt [0:LSM_PLAIN_N-1];
  logic [8:0]  lsm_plain_lcnt [0:LSM_PLAIN_N-1];
  logic [4:0]  lsm_plain_field [0:LSM_PLAIN_N-1];
  logic [23:0] lsm_z12_ph [0:LSM_ZONE_N-1];
  logic [9:0]  lsm_z12_hcnt [0:LSM_ZONE_N-1];
  logic [8:0]  lsm_z12_lcnt [0:LSM_ZONE_N-1];
  logic [23:0] lsm_z16_ph [0:LSM_ZONE_N-1];
  logic [9:0]  lsm_z16_hcnt [0:LSM_ZONE_N-1];
  logic [8:0]  lsm_z16_lcnt [0:LSM_ZONE_N-1];
  always @(posedge CLK) begin
    if (v5_line_start && (u_v5.hpos == 11'd911)) begin
      if (lsm_plain_n < LSM_PLAIN_N) begin
        lsm_plain_ph[lsm_plain_n]    <= u_v5.phase;
        lsm_plain_hcnt[lsm_plain_n]  <= hcnt;
        lsm_plain_lcnt[lsm_plain_n]  <= lcnt;
        lsm_plain_field[lsm_plain_n] <= field;
        lsm_plain_n <= lsm_plain_n + 1;
      end
      if (field == 12 && lcnt >= 9'd100 && lcnt <= 9'd113 &&
          lsm_z12_n < LSM_ZONE_N) begin
        lsm_z12_ph[lsm_z12_n] <= u_v5.phase;
        lsm_z12_hcnt[lsm_z12_n] <= hcnt;
        lsm_z12_lcnt[lsm_z12_n] <= lcnt;
        lsm_z12_n <= lsm_z12_n + 1;
      end
      if (field == 16 && lcnt >= 9'd100 && lcnt <= 9'd113 &&
          lsm_z16_n < LSM_ZONE_N) begin
        lsm_z16_ph[lsm_z16_n] <= u_v5.phase;
        lsm_z16_hcnt[lsm_z16_n] <= hcnt;
        lsm_z16_lcnt[lsm_z16_n] <= lcnt;
        lsm_z16_n <= lsm_z16_n + 1;
      end
    end
  end

  integer fails = 0;

  initial begin
    wait (v5_reset == 1'b0);
    wait (field == 4 && lcnt == 0);
    repeat (1) @(posedge CLK);

    // ---- DEBUG: what is triggering line_start? ----
    $display("=== [dbg] first %0d v5 line_start events (transient) hcnt/hpos/comp/tip ===", dbg_n);
    begin : dbg_block
      integer i;
      for (i = 0; i < dbg_n; i++)
        $display("  #%0d  hcnt=%0d hpos=%0d comp=%0d tip=%0d", i, dbg_hcnt[i], dbg_hpos[i], dbg_comp[i], dbg_tip[i]);
    end

    $display("=== [dbg2] post-transient (field>=2) line_start events (expect ~1/line at hcnt~130) ===");
    begin : dbg2_block
      integer i;
      for (i = 0; i < dbg2_n; i++)
        $display("  #%0d  hcnt=%0d hpos=%0d tip=%0d", i, dbg2_hcnt[i], dbg2_hpos[i], dbg2_tip[i]);
    end

    // ---- Check 1: horizontal lock (line_len ~ 912, hs pulses ~once/line) ----
    $display("=== [1] v5 horizontal lock ===");
    begin : lock_block
      integer i, ll_min = 9999, ll_max = 0, hs_expect;
      for (i = 0; i < 8; i++) begin
        if (line_len_sample[i] < ll_min) ll_min = line_len_sample[i];
        if (line_len_sample[i] > ll_max) ll_max = line_len_sample[i];
      end
      // hs_rises over ~3 fields (fields 1..3, ~3*262 = 786)
      hs_expect = 3 * FIELD_LINES;
      $display("line_len samples (hcnt+1 at line_start, 8): %0d %0d %0d %0d %0d %0d %0d %0d",
               line_len_sample[0], line_len_sample[1], line_len_sample[2],
               line_len_sample[3], line_len_sample[4], line_len_sample[5],
               line_len_sample[6], line_len_sample[7]);
      $display("line_len range [%0d..%0d]  hs_rises=%0d (expect ~%0d over 3 fields)",
               ll_min, ll_max, hs_rises, hs_expect);
      if (ll_min >= 905 && ll_min <= 919 && ll_max <= 919 && ll_max >= 905 &&
          hs_rises >= hs_expect - 6 && hs_rises <= hs_expect + 6)
        $display("PASS (v5 locked to the 912-sample line)");
      else begin
        $display("FAIL (line_len or hs count off: lock not stable)");
        fails = fails + 1;
      end
    end

    // ---- Check 2: RGB non-trivial + black clamp on the porch ----
    wait (field == 8 && lcnt == 0);
    repeat (1) @(posedge CLK);
    $display("=== [2] v5 RGB contrast + black clamp ===");
    $display("active R: min=%0d max=%0d spread=%0d samples=%0d",
             r_min, r_max, r_max - r_min, r_samples);
    begin : contrast_block
      if (r_samples > 0 && (r_max - r_min) > 20 && r_min < 40 && r_max > 50)
        $display("PASS (contrast present; black near blanking -> clamp on porch)");
      else begin
        $display("FAIL (R trivial/constant, black not near 0, or no contrast)");
        fails = fails + 1;
      end
    end

    // ---- Check 3: PHASE_AT_SYNC_RISE constant (re-anchor constant) ----
    $display("=== [3] PHASE_AT_SYNC_RISE (v5.phase at sync rise, 6 lines) ===");
    begin : phase_block
      integer i;
      logic constant = 1'b1;
      for (i = 1; i < 6; i++)
        if (phase_at_sync[i] !== phase_at_sync[0]) constant = 1'b0;
      $display("phase@sync = %08h %08h %08h %08h %08h %08h",
               phase_at_sync[0], phase_at_sync[1], phase_at_sync[2],
               phase_at_sync[3], phase_at_sync[4], phase_at_sync[5]);
      $display("PHASE_AT_SYNC_RISE = 24'h%06h  (top-8 %08h)  constant=%0b",
               phase_at_sync[0], phase_at_sync[0][23:16], constant);
      if (constant)
        $display("PASS (phase at sync rise is line-stable -> re-anchor constant valid)");
      else begin
        $display("FAIL (phase at sync rise not constant -> re-anchor unsafe)");
        fails = fails + 1;
      end
    end

    // ---- Phase 4: F5-LOAD discontinuity (source jump) hue check ----
    // Stall (save) then LOAD from a different saved HBL position (701), giving
    // a (500-701) mod 4 == 3 (270-degree) phase misalignment on an unfixed
    // design. The decoded colour at column 600 must be identical before/after.
    wait (field == 16 && lcnt == 150 && hcnt == 500);
    machine_ce = 1'b0;
    repeat (12345) @(posedge CLK);  // 12345 % 4 = 1
    lcnt = 9'd170;                   // LOAD: resume from a different,
    hcnt = 10'd701;                  // saved HBL position (same colour zone)
    machine_ce = 1'b1;
    wait (post4_captured);
    repeat (2) @(posedge CLK);
    $display("=== [4] v5 F5-LOAD hue (machine_ce low + HBL source jump) ===");
    $display("phase@col600: clean4=%08h  post4=%08h  (diff=%08h)",
             clean4_ph, post4_ph, clean4_ph ^ post4_ph);
    $display("clean4 (pre) R%02X G%02X B%02X   post4 (post) R%02X G%02X B%02X",
             clean4_r, clean4_g, clean4_b, post4_r, post4_g, post4_b);
    begin : load_block
      logic ok;
      ok = (clean4_captured === 1'b1) && (post4_captured === 1'b1) &&
           (clean4_ph === post4_ph);
      if (ok)
        $display("PASS (v5 phase re-anchored to the source across the load)");
      else
        $display("DRIFT (post-load phase rotated by %08h - re-anchor not yet in place, or failed)",
                 clean4_ph ^ post4_ph);
      if (!ok) fails = fails + 1;
      // NOTE: without the re-anchor (Stage 1a) this is EXPECTED to DRIFT;
      // it is gated (must PASS) after the re-anchor (Stage 1b).
    end

    // --- Monitor 5 report (lsmon): steady-state grid at LOCKED edges ---
    $display("=== [lsmon] phase at LOCKED line starts (hpos==911; excludes power-on transient) ===");
    begin : lsmon_block
      integer i;
      $display("  plain  (first 6 locked edges, fields 0-1):");
      for (i = 0; i < lsm_plain_n; i++)
        $display("    #%0d f=%0d l=%0d hcnt=%0d phase=%08h", i,
                 lsm_plain_field[i], lsm_plain_lcnt[i], lsm_plain_hcnt[i],
                 lsm_plain_ph[i]);
      $display("  zone12 (field 12 colour-zone lines, pre-stall):");
      for (i = 0; i < lsm_z12_n; i++)
        $display("    #%0d l=%0d hcnt=%0d phase=%08h", i,
                 lsm_z12_lcnt[i], lsm_z12_hcnt[i], lsm_z12_ph[i]);
      $display("  zone16 (field 16 colour-zone lines, pre-stall):");
      for (i = 0; i < lsm_z16_n; i++)
        $display("    #%0d l=%0d hcnt=%0d phase=%08h", i,
                 lsm_z16_lcnt[i], lsm_z16_hcnt[i], lsm_z16_ph[i]);
    end

    $display("=== summary: fails=%0d (check4 drift is expected pre-re-anchor) ===", fails);
    $finish;
  end

endmodule
`default_nettype wire
