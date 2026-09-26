// video_pipeline.sv
// =====================================================================
// Presentation-pipeline switch for the newsdee core.
//
// Takes the raw 1-bit Apple VIDEO + 14 MHz blanking (HBL/VBL) and produces
// the final RGB + timing that feeds the video_mixer. Two paths, muxed on
// `use_composite`:
//
//   * Native RGB (use_composite = 0): vga_controller (the existing color
//     pipeline). Byte-identical to the pre-composite build.
//   * Composite (use_composite = 1): apple_composite encodes the 1-bit
//     video to an NTSC composite stream in THIS 14 MHz domain, and its
//     loopback decoder turns it back to RGB. The 4-preset tables
//     (Calibrated / Eyeballed / Punchy / Muted) select the decoder knobs;
//     on the v5a "New Color TV" path the P6 OSD states add fine-tune
//     offsets on top of the preset base (the legacy path is unchanged).
//     See ../Apple-II-Verilog_MiSTer/docs/V5A_KNOB_MAPPING_PLAN.md.
//
// The composite path runs in the 14 MHz domain (one sample per clock), the
// level-2-validated domain, with 4x the timing slack of a 57 MHz mixer
// decode. Each path drives its own consistent RGB + timing set, so the
// stock video_mixer (fed by name: HSync/VSync/HBlank/VBlank/core_R/G/B)
// sees a valid picture in either mode.
// =====================================================================

`default_nettype none

// The composite path is the v5a decoder (composite_decoder). The legacy
// "Color TV" decoder was removed 2026-09-24 - see
// ../Apple-II-Verilog_MiSTer/docs/video/COMPOSITE_PRESETS_REFERENCE.md.
module video_pipeline
(
  input  wire        CLK_14M,
  // raw mono tap from the apple2 core
  input  wire        VIDEO,
  input  wire        HBL,
  input  wire        VBL,
  // vga_controller control (native RGB path)
  input  wire        COLOR_LINE,
  input  wire [1:0]  SCREEN_MODE,
  input  wire [1:0]  COLOR_PALETTE,
  input  wire        RUN_FILL_OK,
  input  wire        NTSC_VERTICAL_COMB,
  // custom palette loader (vga_controller ioctl)
  input  wire [24:0] ioctl_addr,
  input  wire [7:0]  ioctl_data,
  input  wire [7:0]  ioctl_index,
  input  wire        ioctl_download,
  input  wire        ioctl_wr,
  output wire        ioctl_wait,
  // Freeze the whole pipeline during a machine stall (save/load, OSD
  // pause): while machine_ce is low the core holds HBL/VBL/VIDEO
  // frozen but the 14 MHz domain keeps running.  If the composite path
  // kept running it would free-run its subcarrier, synthesize phantom
  // lines from the stuck sync, and fill the vertical comb's field RAM
  // with garbage - the decoded hue then lands at a phase-dependent
  // value on resume (a different hue on every save/load attempt).
  // Gating ce freezes encoder/decoder/comb deterministically: the frame
  // holds on screen and resumes exactly where it stopped.
  input  wire        reset,        // machine reset -> composite decoder
  input  wire        machine_ce,
  // composite switch
  input  wire        use_composite,  // "Display Type" != RGB Monitor (status[4:3] != 0)
  input  wire [1:0]  comp_preset,    // 0=Calibrated 1=Eyeballed 2=Punchy 3=Muted
  input  wire        comp_hfix,      // retained for config compatibility; correction is always active
  input  wire [4:0]  comp_hue_adj,   // debug: composite hue adjust 0-31 (added to base hue)
  // v5a (New Color TV) OSD fine-tune knobs (P6 page, status bits [67:64] hue,
  // [54:52] bright, [51:49] sat, [34:33] contrast): state indices mapping to
  // OFFSETS from the selected preset's knob base; default states 4/1/2/1 are
  // zero offsets (the picture is exactly the selected preset; 2026-09-24
  // grid). Applied on the composite (v5a) path.
  // Drive explicitly in TBs (unconnected = X).
  input  wire [3:0]  v5_hue_st,      // (s-4)*4  -> -16..+16  (state 4 = no offset)
  input  wire [2:0]  v5_bright_st,   // (s-1)*16-16 -> -16..+96 (state 1 = no offset)
  input  wire [2:0]  v5_sat_st,      // {-16,-8,0,+8,+16,+32} (state 2 = no offset)
  input  wire [1:0]  v5_contrast_st, // (s-1)*16-16 -> -16..+32 (state 1 = no offset)
  // final outputs (same names/widths vga_controller gave apple2_top)
  output wire [7:0]  R,
  output wire [7:0]  G,
  output wire [7:0]  B,
  output wire        HS,
  output wire        VS,
  output wire        HBL_O,
  output wire        VBL_O
);

  // ------------------------------------------------------------------
  // Native RGB color path (vga_controller)
  // ------------------------------------------------------------------
  // Seam-fix knobs are fixed: the seam fix is always on (its RGB output
  // is discarded in composite mode - the encoder consumes the raw 1-bit
  // VIDEO, so it cannot reach the composite path), the run fill is fixed
  // on/narrow. No top-level ports.
  localparam GRAY_SEAM_FIX = 1'b1;
  localparam SEAM_RUN_FILL = 1'b1;
  localparam SEAM_RUN_WIDE = 1'b0;
  wire [7:0] r_vga, g_vga, b_vga;
  wire       hs_vga, vs_vga, hbl_vga, vbl_vga;
  vga_controller tv (
    .CLK_14M(CLK_14M),
    .VIDEO(VIDEO),
    .COLOR_LINE(COLOR_LINE),
    .SCREEN_MODE(SCREEN_MODE),
    .COLOR_PALETTE(COLOR_PALETTE),
    .GRAY_SEAM_FIX(GRAY_SEAM_FIX),
    .SEAM_RUN_FILL(SEAM_RUN_FILL),
    .SEAM_RUN_WIDE(SEAM_RUN_WIDE),
    .RUN_FILL_OK(RUN_FILL_OK),
    .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),
    .HBL(HBL),
    .VBL(VBL),
    .VGA_HS(hs_vga),
    .VGA_VS(vs_vga),
    .VGA_HBL(hbl_vga),
    .VGA_VBL(vbl_vga),
    .VGA_R(r_vga),
    .VGA_G(g_vga),
    .VGA_B(b_vga),
    .ioctl_addr(ioctl_addr),
    .ioctl_data(ioctl_data),
    .ioctl_index(ioctl_index),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_wait(ioctl_wait)
  );

  // ------------------------------------------------------------------
  // Sync derivation for the composite encoder (14 MHz domain).
  // hs: 68-cycle pulse 130 cycles into HBL; vs: 3 lines 33 lines into VBL.
  // Matches the vga_controller geometry (VGA_FRONT_PORCH=130, VGA_HSYNC=68,
  // VBL_TO_VSYNC=33, VGA_VSYNC_LINES=3) and the level-2 reference.
  // ------------------------------------------------------------------
  localparam [9:0] HSYNC_FRONT_PORCH = 10'd130;
  localparam [9:0] HSYNC_WIDTH       = 10'd68;
  localparam [6:0] VSYNC_FRONT_PORCH = 7'd33;
  localparam [6:0] VSYNC_LINES       = 7'd3;

  reg [9:0] hblank_cnt;
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      if (HBL) hblank_cnt <= hblank_cnt + 10'd1;
      else     hblank_cnt <= 10'd0;
    end
  end

  reg         hbl_d;
  wire        hbl_rise   = HBL & ~hbl_d;
  always @(posedge CLK_14M) if (machine_ce) hbl_d <= HBL;

  reg [6:0]   vblank_lines;
  always @(posedge CLK_14M) begin
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
  // 4-preset knob selection (the ONLY place the presets live): one table
  // per decoder. The legacy "Color TV" table is hardware-tuned in the legacy
  // demod frame. The v5a "New Color TV" table uses the same sat/bright/
  // contrast units (apple_composite does the v5a unit conversion) with the
  // hue column re-based to the v5a demod frame: the v5a verified-correct
  // frame sits at hue 0 while the legacy rows sit at ~112..130, so the
  // legacy RELATIVE offsets vs Calibrated (Eyeballed +13, Punchy +15,
  // Muted -3) are carried over. Calibrated carries the legacy Calibrated
  // numbers (user decision 2026-09-23).
  // Common to all presets: i_mirror=1 (chirality fix), chroma_short=0, pixel_delay=0,
  // luma_gain=2857, setup=0, agc=1 (all fixed inside apple_composite).
  // ------------------------------------------------------------------
  reg  [7:0] p_sat, p_hue, p_bright, p_contrast;
  reg        p_i_mirror;
  reg        p_chroma_short;
  reg  [3:0] p_smear, p_luma_delay;
  reg        p_agc;
  // v5a preset base rows (before the P6 fine-tune offsets are applied).
  reg  [7:0] v5a_sat, v5a_hue, v5a_bright, v5a_contrast;
  // 8-bit clamps for the base+offset sums (16-bit signed intermediates).
  function signed [7:0] clamp_s8(input signed [15:0] v);
    if      (v >  16'sd127)  clamp_s8 = 8'sh81;   // -127
    else if (v < -16'sd127)  clamp_s8 = 8'sh81;   // -127
    else                     clamp_s8 = v[7:0];
  endfunction
  function [7:0] clamp_u8(input signed [15:0] v);
    if      (v >  16'sd255)  clamp_u8 = 8'hFF;
    else if (v <  16'sd0)    clamp_u8 = 8'h00;
    else                     clamp_u8 = v[7:0];
  endfunction
  // Map P6 knob states to knob OFFSETS. Default states (hue 4, bright 1,
  // sat 2, contrast 1) are zero offsets: the picture is exactly the
  // selected preset.
  wire signed [15:0] k_hue_c          = ($signed({9'd0, v5_hue_st}) - 9'sd4) * 16'sd4;     // -16..+16, state 4 = 0
  wire signed [15:0] k_bright_c       = ($signed({6'd0, v5_bright_st}) - 6'sd1) * 16'sd16 - 16'sd16; // -16..+96, state 1 = 0
  logic signed [15:0] k_sat_off_c;
  always @(*) begin
    case (v5_sat_st)
      3'd0: k_sat_off_c = -16'sd16;
      3'd1: k_sat_off_c = -16'sd8;
      3'd2: k_sat_off_c = 16'sd0;
      3'd3: k_sat_off_c = 16'sd8;
      3'd4: k_sat_off_c = 16'sd16;
      default: k_sat_off_c = 16'sd32;   // states 5..7 (OSD list ends at 5): +32
    endcase
  end
  wire signed [15:0] k_contrast_off_c = ($signed({4'd0, v5_contrast_st}) - 4'sd1) * 16'sd16 - 16'sd16; // -16..+32, state 1 = 0
  always @* begin
    // v5a preset table (2026-09-24 grid: Calibrated neutral with the +8 hue
    // base, Muted desaturated); each preset overrides the v5a_* base rows.
    p_i_mirror   = 1'b1;
    p_chroma_short = 1'b0;
    p_smear      = 4'd0;
    p_luma_delay = 4'd0;
    p_agc        = 1'b1;
    case (comp_preset)
      2'd0: begin p_sat=8'd80;  p_hue=8'd115; p_bright=8'hF2; p_contrast=8'd177; end   // Calibrated (hardware-tuned; hue=112 base +3)
      2'd1: begin p_sat=8'd51;  p_hue=8'd128;  p_bright=8'sd10; p_contrast=8'd170; end  // Eyeballed (hardware-tuned)
      2'd2: begin p_sat=8'd100; p_hue=8'd130; p_bright=8'sd9; p_contrast=8'd255; end   // Punchy (AppleWin-like)
      2'd3: begin p_sat=8'd80;  p_hue=8'd112;  p_bright=8'hFB; p_contrast=8'd190; end   // Muted (Eyeballed, sat=80)
      default:   begin end
    endcase
    // v5a base: Calibrated row by default; rows 1-3 override (hue re-based).
    // 2026-09-24 retune #2 (measured, tools/tb_v5a_tune.sv): the first
    // order retune (8'h90/136) overshot (flat white 104 vs legacy 255).
    // Flat-field transfer: v5a neutral (b=0, c=128) = black 0 / white
    // 254 vs legacy Calibrated 0 / 255 => all presets use neutral luma
    // (bright 0, contrast 128); presets differ by sat/hue and P6 V5
    // knobs provide fine trim. Base hue +8 (hardware: Calibrated matches
    // the RGB monitor palette). See
    // ../Apple-II-Verilog_MiSTer/docs/video/COMPOSITE_PRESETS_REFERENCE.md section 2c.
    v5a_sat        = 8'd80;
    v5a_hue        = 8'd8;
    v5a_bright     = 8'd0;
    v5a_contrast   = 8'd128;
    case (comp_preset)
      2'd1: begin v5a_sat=8'd51;  v5a_hue=8'd21;  v5a_bright=8'd0;  v5a_contrast=8'd128; end  // Eyeballed (+13 vs Calibrated, base +8)
      2'd2: begin v5a_sat=8'd100; v5a_hue=8'd23;  v5a_bright=8'd0;  v5a_contrast=8'd128; end   // Punchy (+15 vs Calibrated, base +8)
      2'd3: begin v5a_sat=8'd48;  v5a_hue=8'd5;   v5a_bright=8'd0; v5a_contrast=8'd128; end   // Muted (desaturated, -3 vs Calibrated, base +8)
      default:   begin end
    endcase
    // v5a knobs = preset base + P6 offset: hue wraps mod 256, the rest
    // clamps to the 8-bit port range.
    p_hue      = v5a_hue + k_hue_c[7:0];
    p_bright   = clamp_s8($signed(v5a_bright) + k_bright_c);
    p_sat      = clamp_u8($signed({8'd0, v5a_sat}) + k_sat_off_c);   // zero-extend: values >= 128 sign-extend negative as 8-bit signed
    p_contrast = clamp_u8($signed({8'd0, v5a_contrast}) + k_contrast_off_c); // zero-extend: same trap (177 = -79 as 8-bit signed)
  end

  // ------------------------------------------------------------------
  // Composite path: encode 1-bit video -> NTSC composite -> decode RGB.
  // ------------------------------------------------------------------
  wire [7:0]  r_comp, g_comp, b_comp;
  wire        hs_c_out, vs_c_out, hb_c_out, vb_c_out;
  // ce_out and comp_sample are apple_composite testability ports, not needed
  // in the core build (the 14 MHz domain is always enabled; comp_sample is
  // the raw encoder stream). Left unconnected on purpose.
  /* verilator lint_off PINMISSING */
  apple_composite #(.V5_AXIS(V5_AXIS), .V5_Q_NEG(V5_Q_NEG)) u_comp (
    .clk(CLK_14M),
    .reset(reset),
    .ce(machine_ce),
    .video(VIDEO),
    .pixel_delay(2'd0),
    .hs(hs_c),
    .vs(vs_c),
    .hb(HBL),
    .vb(VBL),
    .color_line(COLOR_LINE),
    .sat(p_sat),
    .hue(p_hue + comp_hue_adj),
    .bright(p_bright),
    .contrast(p_contrast),
    .i_mirror(p_i_mirror),
    .chroma_short(p_chroma_short),
    .smear(p_smear),
    .luma_delay(p_luma_delay),
    .agc_en(p_agc),
    .comb_en(NTSC_VERTICAL_COMB),
    .r(r_comp),
    .g(g_comp),
    .b(b_comp),
    .hs_out(hs_c_out),
    .vs_out(vs_c_out),
    .hb_out(hb_c_out),
    .vb_out(vb_c_out)
  );
  /* verilator lint_on PINMISSING */

  // ------------------------------------------------------------------
  // Composite horizontal shift (composite path only).
  //
  // The composite timing (hb/hs, derived from the decoded stream) lands a
  // few samples off from the native vga_controller timing, so the composite
  // picture reads as shifted. Delay the composite TIMING by hshift_idx cycles
  // (RGB untouched) to slide the active window. The native RGB path is the
  // correctly centred reference and is never touched.
  //
  // The required delay is decoder-specific (tools/tb_hoffset.sv, measured
  // 2026-09-23 against the native path, field 2 of a stable frame):
  //   v5a composite_decoder    : HSHIFT_V5 = 9
  //     One fewer sample clock exposes the final Apple pixel and aligns the
  //     decoded bars with the native active window.
  // ------------------------------------------------------------------
  // TB-measured composite alignment delays. PARAMETERS (not localparams) so
  // tb_hoffset can override them per instance when re-measuring.
  parameter HSHIFT_V5     = 9;  // v5a decoder (measured 2026-09-26)
  // v5a colour-frame knobs, threaded to apple_composite
  // (tb_v5_color sweep + hardware 2026-09-23): AXIS=0 matches the legacy
  // frame; Q_NEG=0 keeps the natural Q sign (1 = green<->purple mirror).
  parameter V5_AXIS  = 0;
  parameter V5_Q_NEG = 0;
  localparam HSHIFT_MAX  = HSHIFT_V5;
  localparam HSHIFT_PIPE = HSHIFT_MAX + 3;  // pipe must reach HSHIFT_MAX (+3 margin)
  reg  [HSHIFT_PIPE:0] hb_c_pipe, hs_c_pipe;  // stages 0..HSHIFT_PIPE
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      hb_c_pipe <= {hb_c_pipe[HSHIFT_PIPE-1:0], hb_c_out};
      hs_c_pipe <= {hs_c_pipe[HSHIFT_PIPE-1:0], hs_c_out};
    end
  end
  wire [3:0] hshift_idx = HSHIFT_V5[3:0];
  wire       hb_c_s = hb_c_pipe[hshift_idx];
  wire       hs_c_s = hs_c_pipe[hshift_idx];

  // ------------------------------------------------------------------
  // Monochrome phosphor emulation (Display Mode B&W / Green / Amber).
  //
  // The composite path is 2-level luma; in mono mode the machine's color
  // killer drops the burst, so the decoded output carries no chroma
  // (r ~ g ~ b = gray). Snap that gray to the mode's two phosphor colors,
  // matching the RGB path's 2-color screen (vga_controller values). Color
  // mode (00) is untouched -> bit-identical.
  // ------------------------------------------------------------------
  localparam [23:0] W_BW = 24'hFFFFFF, K_BW = 24'h000000;
  localparam [23:0] W_GR = 24'h00C001, K_GR = 24'h000F01;  // vga green
  localparam [23:0] W_AM = 24'hFF8001, K_AM = 24'h200801;  // vga amber
  logic [23:0] mono_w, mono_k;
  always @(*) begin
    case (SCREEN_MODE)
      2'b01: begin mono_k = K_BW; mono_w = W_BW; end
      2'b10: begin mono_k = K_GR; mono_w = W_GR; end
      2'b11: begin mono_k = K_AM; mono_w = W_AM; end
      default: begin mono_k = K_BW; mono_w = W_BW; end
    endcase
  end
  wire mono_on = g_comp >= 8'd128;  // decoded gray: black..white
  wire [7:0] r_mono = mono_on ? mono_w[23:16] : mono_k[23:16];
  wire [7:0] g_mono = mono_on ? mono_w[15:8]  : mono_k[15:8];
  wire [7:0] b_mono = mono_on ? mono_w[7:0]   : mono_k[7:0];

  // ------------------------------------------------------------------
  // Final mux. Each path drives its own consistent RGB + timing set.
  // ------------------------------------------------------------------
  assign R     = use_composite ? (SCREEN_MODE != 2'b00 ? r_mono : r_comp) : r_vga;
  assign G     = use_composite ? (SCREEN_MODE != 2'b00 ? g_mono : g_comp) : g_vga;
  assign B     = use_composite ? (SCREEN_MODE != 2'b00 ? b_mono : b_comp) : b_vga;
  assign HS    = use_composite ? hs_c_s     : hs_vga;
  assign VS    = use_composite ? vs_c_out   : vs_vga;
  assign HBL_O = use_composite ? hb_c_s     : hbl_vga;
  assign VBL_O = use_composite ? vb_c_out   : vbl_vga;

endmodule

`default_nettype wire
