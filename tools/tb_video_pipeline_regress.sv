// tb_video_pipeline_regress.sv
// =====================================================================
// Differential regression test for video_pipeline (NOT a Quartus source;
// build with Verilator only, see the run command in COMPOSITE_PROGRESS.md).
//
// Proves that with use_composite=0 the video_pipeline output (RGB + timing)
// is byte-identical to a bare vga_controller given the same raw 1-bit video.
// This is the "no regression to the existing VGA path" guarantee.
//
// A synthetic 14 MHz NTSC-ish signal (912-cycle line, 352 HBL + 560 active,
// 3-line VBL, 262-line field) is fed to both a reference vga_controller and
// the video_pipeline (use_composite=0). Every active-field sample is compared.
// =====================================================================
`timescale 1ns/1ps
module tb_video_pipeline_regress;

  // 14.318 MHz
  reg CLK = 1'b0;
  always #35 CLK = ~CLK;

  // Geometry (matches this core: 912-cycle line, 352 HBL + 560 active).
  localparam int LINE_LEN    = 912;
  localparam int HBL_LEN     = 352;
  localparam int FIELD_LINES = 262;
  localparam int VBL_LINES   = 3;

  reg [9:0] hcnt = 0;
  reg [8:0] lcnt = 0;
  reg [4:0] field = 0;  // 5 bits so it can reach 16 (phase 4)

  wire HBL = (hcnt < HBL_LEN);
  wire VBL = (lcnt < VBL_LINES);

  // 1-bit video: a spatial pattern while active, 0 during blanking (the
  // real video_generator forces VIDEO=0 in HBL).
  // Phase-3 color zone: in field 12, lcnt 100..199 the video flips at the
  // subcarrier rate (hcnt[1] = 14M/4 = fsc) - like real 4-bit-HGR color -
  // so the composite signal carries real chroma and a post-stall hue drift
  // is visible in the decoded RGB. Phase 4 repeats the zone in field 16
  // (the load-discontinuity test needs its own clean reference + post
  // pixels, so it cannot reuse field 12).
  wire color_zone  = (field == 12) && (lcnt >= 100) && (lcnt < 200) && !HBL;
  wire color_zone2 = (field == 16) && (lcnt >= 100) && (lcnt < 200) && !HBL;
  wire VIDEO = HBL ? 1'b0 : (color_zone || color_zone2) ? hcnt[1] : (hcnt[8] ^ hcnt[2] ^ lcnt[4]);

  // machine_ce: models the savestate manager / OSD-pause machine enable.
  // Low = the core's timing generator holds HBL/VBL/VIDEO frozen while the
  // 14 MHz domain keeps running (the real save/load behavior).
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

  // Fixed, typical color-mode control.
  wire        COLOR_LINE = 1'b1;  // color on: exercises the burst (phase 2)
  wire [1:0]  SCREEN_MODE   = 2'b00;  // color
  wire [1:0]  COLOR_PALETTE = 2'b00;
  wire        GRAY_SEAM_FIX  = 1'b1;
  wire        SEAM_RUN_FILL  = 1'b1;
  wire        SEAM_RUN_WIDE  = 1'b0;
  wire        RUN_FILL_OK    = 1'b1;
  wire        NTSC_VERTICAL_COMB = 1'b0;
  wire [24:0] ioctl_addr     = 25'd0;
  wire [7:0]  ioctl_data     = 8'd0;
  wire [7:0]  ioctl_index    = 8'd0;
  wire        ioctl_download = 1'b0;
  wire        ioctl_wr       = 1'b0;

  // Reference: bare vga_controller.
  wire [7:0] ref_r, ref_g, ref_b;
  wire ref_hs, ref_vs, ref_hbl, ref_vbl, ref_wait;
  vga_controller u_ref (
    .CLK_14M(CLK), .VIDEO(VIDEO), .COLOR_LINE(COLOR_LINE),
    .SCREEN_MODE(SCREEN_MODE), .COLOR_PALETTE(COLOR_PALETTE),
    .GRAY_SEAM_FIX(GRAY_SEAM_FIX), .SEAM_RUN_FILL(SEAM_RUN_FILL),
    .SEAM_RUN_WIDE(SEAM_RUN_WIDE), .RUN_FILL_OK(RUN_FILL_OK),
    .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),
    .HBL(HBL), .VBL(VBL),
    .VGA_HS(ref_hs), .VGA_VS(ref_vs), .VGA_HBL(ref_hbl), .VGA_VBL(ref_vbl),
    .VGA_R(ref_r), .VGA_G(ref_g), .VGA_B(ref_b),
    .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_index(ioctl_index),
    .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_wait(ref_wait)
  );

  // DUT: video_pipeline. use_composite is a reg so phase 2 can flip it on.
  reg use_composite = 1'b0;
  wire [7:0] dut_r, dut_g, dut_b;
  wire dut_hs, dut_vs, dut_hbl, dut_vbl, dut_wait;
  video_pipeline dut (
    .CLK_14M(CLK), .VIDEO(VIDEO), .HBL(HBL), .VBL(VBL),
    .machine_ce(machine_ce),
    .COLOR_LINE(COLOR_LINE), .SCREEN_MODE(SCREEN_MODE), .COLOR_PALETTE(COLOR_PALETTE),
    .RUN_FILL_OK(RUN_FILL_OK),
    .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),
    .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_index(ioctl_index),
    .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_wait(dut_wait),
    .use_composite(use_composite), .comp_preset(2'd0), .comp_hshift(2'd0), .comp_hue_adj(5'd0),
    .R(dut_r), .G(dut_g), .B(dut_b),
    .HS(dut_hs), .VS(dut_vs), .HBL_O(dut_hbl), .VBL_O(dut_vbl)
  );

  // Phase-3 monitors: (a) while machine_ce is low the DUT outputs must not
  // change at all (frozen frame, no phantom lines); (b) the decoded R/G/B at
  // the same fixed pixel before and after the stall must be identical (no
  // hue drift of the free-running subcarrier/phase accumulator).
  integer     stall_changes = 0;
  logic [7:0] hold_r, hold_g, hold_b;
  logic       hold_hs, hold_vs, hold_armed;
  logic [7:0] pre_r, pre_g, pre_b, post_r, post_g, post_b;
  logic       pre_captured, post_captured;
  // Phase-4 (load-discontinuity) capture: clean reference and post-load
  // pixel in the field-16 color zone, plus the re-anchored phase at the
  // first hs fall after resume.
  logic [7:0] clean4_r, clean4_g, clean4_b, post4_r, post4_g, post4_b;
  logic       clean4_captured, post4_captured;
  logic [1:0] k_inv, k_after;
  logic [7:0] k_inv_dec;
  logic       k_const = 1'b1;
  integer     fails = 0;
  // Synchronous re-anchor-edge sampler. The re-anchor writes on the
  // posedge where the pre-edge (hs_d && !hs) holds (the same edge hcnt
  // resets on); fall_flag is high one cycle after that edge, so the
  // delayed read below sees the post-write value - the re-anchor
  // constant itself during normal operation.
  reg        fall_flag;
  reg [1:0]  k_edge;
  reg [7:0]  k_edge_dec;
  reg        k_edge_pulse;
  reg        p4_armed, p4_fired;
  always @(posedge CLK) begin
    fall_flag <= dut.u_comp.hs_d && !dut.u_comp.hs;
    if (fall_flag) begin
      k_edge       <= dut.u_comp.burst_cnt;
      k_edge_dec   <= dut.u_comp.u_dec.phase;
      k_edge_pulse <= 1'b1;
      if (p4_armed) begin
        k_after    <= dut.u_comp.burst_cnt;
        p4_armed   <= 1'b0;
        p4_fired   <= 1'b1;
      end
    end else
      k_edge_pulse <= 1'b0;
  end

  always @(posedge CLK) begin
    if (!machine_ce) begin
      if (hold_armed) begin
        if (hold_r !== dut_r || hold_g !== dut_g || hold_b !== dut_b ||
            hold_hs !== dut_hs || hold_vs !== dut_vs)
          stall_changes = stall_changes + 1;
      end else
        hold_armed <= 1'b1;
      hold_r <= dut_r; hold_g <= dut_g; hold_b <= dut_b;
      hold_hs <= dut_hs; hold_vs <= dut_vs;
    end else begin
      hold_armed <= 1'b0;
      hold_r <= dut_r; hold_g <= dut_g; hold_b <= dut_b;
      hold_hs <= dut_hs; hold_vs <= dut_vs;
    end

    if (use_composite && field == 12 && lcnt == 120 && hcnt == 600) begin
      pre_r <= dut_r; pre_g <= dut_g; pre_b <= dut_b;
      pre_captured <= 1'b1;
    end
    if (use_composite && field == 12 && lcnt == 180 && hcnt == 600) begin
      post_r <= dut_r; post_g <= dut_g; post_b <= dut_b;
      post_captured <= 1'b1;
    end
    if (use_composite && field == 16 && lcnt == 120 && hcnt == 600) begin
      clean4_r <= dut_r; clean4_g <= dut_g; clean4_b <= dut_b;
      clean4_captured <= 1'b1;
    end
    if (use_composite && field == 16 && lcnt == 180 && hcnt == 600) begin
      post4_r <= dut_r; post4_g <= dut_g; post4_b <= dut_b;
      post4_captured <= 1'b1;
    end
  end

  // Compare every active-field sample, after the first field (X settling).
  integer mismatches = 0;
  integer samples = 0;
  always @(posedge CLK) begin
    if (!use_composite && field >= 1 && lcnt >= VBL_LINES) begin
      samples = samples + 1;
      if (dut_r !== ref_r || dut_g !== ref_g || dut_b !== ref_b ||
          dut_hs !== ref_hs || dut_vs !== ref_vs ||
          dut_hbl !== ref_hbl || dut_vbl !== ref_vbl) begin
        mismatches = mismatches + 1;
        if (mismatches < 10)
          $display("MISMATCH @%0t f=%0d l=%0d h=%0d: dut R%02X G%02X B%02X hs=%b vs=%b hb=%b vb=%b | ref R%02X G%02X B%02X hs=%b vs=%b hb=%b vb=%b",
            $time, field, lcnt, hcnt,
            dut_r, dut_g, dut_b, dut_hs, dut_vs, dut_hbl, dut_vbl,
            ref_r, ref_g, ref_b, ref_hs, ref_vs, ref_hbl, ref_vbl);
      end
    end
  end

  // Composite sanity: when use_composite=1, the active-video R should show
  // contrast (min/max spread) and non-zero pixels -> the encode->decode
  // wiring (sync derivation + burst + decoder) is alive.
  integer comp_samples = 0;
  integer comp_min = 256, comp_max = -1;
  integer comp_nonzero = 0;
  always @(posedge CLK) begin
    if (use_composite && field >= 6 && lcnt >= VBL_LINES) begin
      comp_samples = comp_samples + 1;
      if (int'(dut_r) < comp_min) comp_min = int'(dut_r);
      if (int'(dut_r) > comp_max) comp_max = int'(dut_r);
      if (dut_r != 0 || dut_g != 0 || dut_b != 0) comp_nonzero = comp_nonzero + 1;
    end
  end

  initial begin
    wait (field == 4);
    repeat (1) @(posedge CLK);
    $display("=== video_pipeline regress (use_composite=0 vs bare vga_controller) ===");
    $display("fields=%0d samples=%0d mismatches=%0d", field, samples, mismatches);
    if (mismatches == 0) $display("PASS");
    else                 $display("FAIL");

    // Phase 2: flip to composite and check the decode produces contrast.
    use_composite = 1'b1;
    wait (field == 8);
    repeat (1) @(posedge CLK);
    $display("=== video_pipeline composite sanity (use_composite=1) ===");
    $display("comp_samples=%0d Rmin=%0d Rmax=%0d nonzero=%0d",
             comp_samples, comp_min, comp_max, comp_nonzero);
    if (comp_samples > 0 && comp_nonzero > 0 && comp_max > 50 &&
        (comp_max - comp_min) > 20)
      $display("PASS (composite path produces contrast)");
    else
      $display("FAIL (composite path trivial/constant)");

    // Phase 2.5: capture the steady-state free-run phase at the derived
    // hs falling edge over six consecutive lines. The line length is a
    // whole number of subcarrier samples (912 = 4*228), so this value
    // must be constant - the lockstep invariant the whole composite path
    // relies on - and the decoder's 8-bit phase must carry the encoder's
    // 2-bit burst counter in its top bits (common reset, common ce).
    // These are the re-anchor constants used by apple_composite and
    // composite_decoder: the board's steady-state value equals the TB's
    // (tb_hbl_pwrup: the board's HBLANK steady-state line grid sits on a
    // multiple of 912 from power-on, and 912 % 4 == 0).
    wait (field == 10 && lcnt == 200);
    repeat (1) @(posedge CLK);
    for (int i = 0; i < 6; i++) begin
      while (!k_edge_pulse) @(posedge CLK);
      if (i == 0) begin
        k_inv     = k_edge;
        k_inv_dec = k_edge_dec;
      end else if (k_edge !== k_inv || k_edge_dec !== k_inv_dec)
        k_const = 1'b0;
      @(posedge CLK);
    end
    $display("=== steady-state phase at hs fall (re-anchor constants) ===");
    $display("K_enc=%02b K_dec=%03d  constant=%0b dec=={enc,6'b0}:%0b",
             k_inv, k_inv_dec, k_const, (k_inv_dec === {k_inv, 6'b0}));
    if (!k_const || (k_inv_dec !== {k_inv, 6'b0})) begin
      $display("FAIL (steady-state phase not constant or pair offset wrong)");
      fails = fails + 1;
    end else
      $display("PASS (lockstep invariant holds)");

    // Phase 3: machine_ce stall (save/load model). The core's timing
    // generator holds HBL/VBL/VIDEO frozen while the 14 MHz domain keeps
    // running; the composite pipeline must freeze with it and resume at the
    // same color phase.
    wait (field == 12 && lcnt == 150 && hcnt == 500);
    machine_ce = 1'b0;
    repeat (12345) @(posedge CLK);  // 12345 % 4 = 1: 90-degree drift if unfixed
    machine_ce = 1'b1;
    wait (post_captured);
    repeat (1) @(posedge CLK);
    $display("=== video_pipeline stall-hold + hue-hold (machine_ce low) ===");
    $display("stall_changes=%0d (want 0)  pre R%02X G%02X B%02X  post R%02X G%02X B%02X",
             stall_changes, pre_r, pre_g, pre_b, post_r, post_g, post_b);
    begin : stall_check
      logic ok;
      // pre R15 G72 Bff is the pre-fix (free-running) golden: the
      // re-anchor must be a bit-identical no-op in normal operation.
      ok = (pre_captured === 1'b1) && (stall_changes == 0) &&
           (pre_r === 8'h15 && pre_g === 8'h72 && pre_b === 8'hff) &&
           (pre_r === post_r && pre_g === post_g && pre_b === post_b);
      if (ok) $display("PASS (frame holds during stall; hue preserved)");
      else begin
        $display("FAIL (outputs moved during stall or hue changed)");
        fails = fails + 1;
      end
    end

    // Phase 4: savestate LOAD discontinuity. The 01e9d48 gate freezes the
    // pipeline during the stall, but a LOAD resumes the machine from the
    // SAVED HBL position (the timing generator's counters are restored),
    // not the stalled position. The free-running subcarrier/decoder phases
    // keep their frozen values and lose lockstep with the core's HBL by
    // (h_stall - h_resume) mod 4 subcarrier samples - an arbitrary hue
    // rotation per attempt. The hs-fall re-anchor must restore the
    // invariant phase within one line. h_resume=701 gives a 270-degree
    // misalignment on an un-fixed design ((500-701) % 4 == 3).
    wait (field == 16 && lcnt == 150 && hcnt == 500);
    machine_ce = 1'b0;
    repeat (12345) @(posedge CLK);  // same 1 mod 4 stall as phase 3
    lcnt = 9'd170;                  // LOAD: resume from a different,
    hcnt = 10'd701;                 // saved HBL position (same color zone)
    machine_ce = 1'b1;
    p4_armed = 1'b1;                 // capture the first re-anchor edge
    while (!p4_fired) @(posedge CLK); // after resume
    @(posedge CLK);
    wait (post4_captured);
    repeat (1) @(posedge CLK);
    $display("=== video_pipeline load discontinuity (machine_ce low + source jump) ===");
    $display("k_inv=%02b k_after=%02b  clean R%02X G%02X B%02X  post4 R%02X G%02X B%02X  stall_changes=%0d",
             k_inv, k_after, clean4_r, clean4_g, clean4_b,
             post4_r, post4_g, post4_b, stall_changes);
    begin : load_check
      logic ok;
      ok = (clean4_captured === 1'b1) && (post4_captured === 1'b1) &&
           (k_after === k_inv) && (stall_changes == 0) &&
           (post4_r === clean4_r && post4_g === clean4_g && post4_b === clean4_b);
      if (ok) $display("PASS (re-anchored within one line; hue preserved after load)");
      else begin
        $display("FAIL (post-load phase/hue drifted - load discontinuity not corrected)");
        fails = fails + 1;
      end
    end

    if (fails == 0) $display("ALL PASS");
    else            $display("FAILURES: %0d", fails);
    $finish;
  end

endmodule
