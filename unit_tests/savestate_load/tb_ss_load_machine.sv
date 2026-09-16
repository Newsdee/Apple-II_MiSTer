// tb_ss_load_machine.sv
//
// LOAD-ONLY machine-level savestate harness.
//
// What it does:
//   * Boots the REAL machine top (Apple-II_MiSTer/rtl/apple2_top.v, +define+SIM_FAST:
//     no HDD / superserial / mouse / NSC) plus the real savestate_manager, with the
//     wrapper's RAM fabric (two dpram instances, machine on port A, manager on port
//     B) replicated exactly from Apple-II.sv.
//   * Preloads the manager's 128 KiB slot memory from a real hardware miosd
//     savestate file (a `savestates/Apple-II/<disk>_1.ss`, 131336 bytes).
//   * Pulses request_load for one cycle (slot 0) and verifies the restore.
//
// File layout (verified against miosd process_ss + two hardware .ss files):
//   bytes  0..15   slot words 0-1: {counter, size, magic=0x41324C31, version, cpu}
//   bytes  16..127 slot words 2-15: reserved (zero on hardware)
//   bytes  128..215 slot words 16-26: the 11 register words (ss_addr 0..10)
//   bytes  256..131327 slot words 32..16415: 131072 RAM bytes
//               byte N (0..65535)   = main RAM byte N
//               byte N (65536..131071) = aux RAM byte N-65536
//   manager reads: header words 0-1, reg words 16..26, RAM words 32..16415
//   (words 27..31 are never read on load; RAM is main-first, then aux)
//
// Checks:
//   C1  load handshake: done=1, error=0
//   C2  RAM sample match vs file (main + aux, strided samples via port B)
//   C3  register word readback vs file (ss_addr 0..10, words 16..26)
//   C4  machine liveness after load: cpu_frozen clears, RAM writes occur,
//       hsync keeps toggling (machine resumes from the saved state)
//
// CPU-type note: the manager rejects a load when the cpu_type input at request
// time != the cpu bit of slot word 1 (error 3). The hardware files carry cpu=1
// (//e / 65C02), so the TB drives cpu_type=1.
//
// Build/run: run_load_test.sh (see AGENTS.md unit-test ladder setup; Verilator
// --binary --timing, chained build+run, CWD at the Apple-II_MiSTer root so the
// ROM $readmemh paths resolve).

`timescale 1ns / 1ps

module tb_ss_load_machine;

  // ---------------------------------------------------------------- clocks
  // Two free-running host clocks, uncorrelated (as on MiSTer): clk_sys feeds
  // the top's CLK_14M fabric port AND the manager (Apple-II.sv: .CLK_14M(clk_sys),
  // manager .clk(clk_sys)); CLK_50M is the second host clock.
  localparam real SYS_HALF = 10.0;    // 50 MHz class
  localparam real CLK50_HALF = 10.417; // 48 MHz class

  reg clk_sys = 1'b0;
  reg clk_50m = 1'b0;
  always #(SYS_HALF)   clk_sys = ~clk_sys;
  always #(CLK50_HALF) clk_50m = ~clk_50m;

  // ---------------------------------------------------------------- state file
  localparam int STATE_WORDS = 16416;  // 128 KiB / 8
  localparam int STATE_BYTES = 131072;
  localparam string STATE_HEX = "unit_tests/savestate_load/build/state.hex";

  reg [7:0] file_bytes [0:131335];     // full .ss file, 1 byte per element
  initial begin
    $readmemb(STATE_HEX, file_bytes);
    $display("INFO file_bytes[0..15] = %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x",
      file_bytes[0], file_bytes[1], file_bytes[2], file_bytes[3],
      file_bytes[4], file_bytes[5], file_bytes[6], file_bytes[7],
      file_bytes[8], file_bytes[9], file_bytes[10], file_bytes[11],
      file_bytes[12], file_bytes[13], file_bytes[14], file_bytes[15]);
  end

  // ---------------------------------------------------------------- DUT wires
  // machine top
  wire soft_reset;
  wire cpu_frozen;
  wire        ram_we;
  wire [7:0]  ram_di;   // top's write data port is 8-bit (wrapper feeds byte 0)
  wire [17:0] ram_addr;
  wire        ram_aux;
  wire [63:0] top_ss_rdata;
  wire hsync, vsync, hblank, vblank;
  wire [7:0] r, g, b;

  // manager
  wire        mgr_machine_ce, mgr_stall;
  wire        ss_busy, ss_done, ss_error, ss_locked_cpu;
  wire [1:0]  ss_error_code;
  wire [9:0]  mgr_ss_addr;
  wire [63:0] mgr_ss_wdata;
  wire        mgr_ss_wren;
  wire        mgr_ram_bank, mgr_ram_rd, mgr_ram_wr;
  wire [15:0] mgr_ram_addr;
  wire [7:0]  mgr_ram_wdata, mgr_ram_rdata;
  wire [14:0] sl_addr;
  wire        sl_rd, sl_wr;
  wire [63:0] sl_wdata;
  reg  [63:0] sl_rdata;

  // ---------------------------------------------------------------- RAM fabric
  // (replicates Apple-II.sv lines 730-783, minus the saturn bank which the
  //  manager never touches: ram_bank is 1 bit, main/aux)
  reg [15:0] tb_probe_addr;
  reg        tb_probe = 1'b0;
  wire [15:0] portb_addr = tb_probe ? tb_probe_addr : mgr_ram_addr;

  wire [7:0] main_qa, main_qb, aux_qa, aux_qb;
  wire ram_main_select = ram_addr[17:16] == 2'b00;
  wire ram_machine_write = ram_we && !ss_busy;
  wire [15:0] ram_dout;

  dpram #(16, 8) main_ram (
    .address_a(ram_addr[15:0]), .address_b(portb_addr),
    .clock_a(clk_sys), .clock_b(clk_sys),
    .data_a(ram_di), .data_b(mgr_ram_wdata),
    .enable_a(1'b1), .enable_b(1'b1),
    .wren_a(ram_machine_write && !ram_aux && ram_main_select),
    .wren_b(mgr_ram_wr && !mgr_ram_bank),
    .q_a(main_qa), .q_b(main_qb)
  );
  dpram #(16, 8) aux_ram (
    .address_a(ram_addr[15:0]), .address_b(portb_addr),
    .clock_a(clk_sys), .clock_b(clk_sys),
    .data_a(ram_di), .data_b(mgr_ram_wdata),
    .enable_a(1'b1), .enable_b(1'b1),
    .wren_a(ram_machine_write && ram_aux),
    .wren_b(mgr_ram_wr && mgr_ram_bank),
    .q_a(aux_qa), .q_b(aux_qb)
  );
  always @(posedge clk_sys) begin
    ram_dout[7:0]  <= ram_main_select ? main_qa : 8'd0;
    ram_dout[15:8] <= aux_qa;
  end
  assign mgr_ram_rdata = mgr_ram_bank ? aux_qb : main_qb;

  // ---------------------------------------------------------------- ss bus
  // wrapper muxes word 10 = active_cpu (Apple-II.sv:403,781); the top serves
  // all other words (8 = flash/reset, 9 = speaker, rest = core via apple2.v).
  wire tb_current_cpu = 1'b1;                       // //e, matches the files
  wire tb_active_cpu  = ss_busy ? ss_locked_cpu : tb_current_cpu;
  wire [9:0]  top_ss_addr = ss_busy ? mgr_ss_addr : tb_ss_probe_addr;
  wire [63:0] ss_rdata_mux = (top_ss_addr == 10'd10) ? {63'd0, tb_active_cpu} : top_ss_rdata;
  reg [9:0] tb_ss_probe_addr = 10'd0;

  // ---------------------------------------------------------------- machine top
  apple2_top u_top (
    .CLK_14M(clk_sys),
    .CLK_50M(clk_50m),
    .reset_cold(dd_reset),
    .reset_warm(1'b0),
    .soft_reset(soft_reset),
    .cpu_type(tb_active_cpu),
    .CPU_WAIT(1'b0),
    .cpu_stall(ss_busy),
    .ss_addr(top_ss_addr),
    .ss_wdata(mgr_ss_wdata),
    .ss_wren(mgr_ss_wren),
    .ss_rdata(top_ss_rdata),
    .machine_ce(mgr_machine_ce && !dd_reset),
    .cpu_frozen(cpu_frozen),
    .ram_we(ram_we),
    .ram_di(ram_di),
    .ram_do(ram_dout),
    .ram_addr(ram_addr),
    .ram_aux(ram_aux),
    .ioctl_addr(16'd0),
    .ioctl_data(8'd0),
    .ioctl_index(4'd0),
    .ioctl_download(1'b0),
    .ioctl_wr(1'b0),
    .ioctl_wait(),
    .hsync(hsync),
    .vsync(vsync),
    .hblank(hblank),
    .vblank(vblank),
    .r(r),
    .g(g),
    .b(b),
    .SCREEN_MODE(2'd0),
    .TEXT_COLOR(1'b0),
    .COLOR_PALETTE(2'd0),
    .NTSC_VERTICAL_COMB(1'b1),
    .use_composite(1'b1),
    .comp_preset(2'd0),
    .comp_hfix(1'b0),
    .comp_hue_adj(8'd0),
    .PALMODE(1'b0),
    .ROMSWITCH(1'b1),
    .PS2_Key(1'b0),
    .virtual_keyboard_active(1'b0),
    .virtual_keyboard_event(1'b0),
    .virtual_keyboard_pressed(1'b0),
    .virtual_keyboard_code(8'd0),
    .virtual_control(1'b0),
    .virtual_open_apple(1'b0),
    .virtual_closed_apple(1'b0),
    .joy(7'd0),
    .joy_an(7'd0),
    .JOY_TO_KEY_EN(1'b0),
    // WOZ SD host channels: no media in the TB
    .SD_LBA0(), .SD_RD0(), .SD_WR0(), .SD_ACK0(1'b0), .SD_BUFF_DIN0(),
    .SD_LBA1(), .SD_RD1(), .SD_WR1(), .SD_ACK1(1'b0), .SD_BUFF_DIN1(),
    .SD_BUFF_ADDR(9'd0),
    .SD_BUFF_DOUT(8'd0),
    .SD_BUFF_WR(1'b0),
    .IMG_MOUNTED0(1'b0),
    .IMG_MOUNTED1(1'b0),
    .IMG_READONLY(1'b0),
    .IMG_SIZE(32'd0),
    .D1_ACTIVE(), .D2_ACTIVE(),
    .D1_MOTOR_ON(), .D2_MOTOR_ON(),
    .D1_IO_ACTIVE(), .D2_IO_ACTIVE(),
    .D1_STEP_ACTIVE(), .D2_STEP_ACTIVE(),
    .D1_TRACK_ZERO_STEP(), .D2_TRACK_ZERO_STEP(),
    .D1_WP(1'b0), .D2_WP(1'b0),
    .DISK_ACT(), .DISK_READY(),
    .HDD_SECTOR(), .HDD_READ(), .HDD_WRITE(),
    .HDD_MOUNTED(1'b0), .HDD_PROTECT(1'b0),
    .HDD_RAM_ADDR(9'd0), .HDD_RAM_DI(8'd0), .HDD_RAM_DO(), .HDD_RAM_WE(1'b0),
    .AUDIO_L(), .AUDIO_R(),
    .TAPE_IN(1'b0),
    .UART_TXD(), .UART_RXD(1'b0), .UART_RTS(), .UART_CTS(1'b0),
    .UART_DTR(), .UART_DSR(1'b0),
    .RTC(1'b0),
    .mouse_strobe(1'b0),
    .mouse_x(8'd0),
    .mouse_y(8'd0),
    .mouse_button(1'b0),
    .mouse_4_inslot(1'b0),
    .mouse_5_inslot(1'b0),
    .mb_4_inslot(1'b0),
    .mb_5_inslot(1'b0),
    .saturn_5_inslot(1'b0)
  );

  // ---------------------------------------------------------------- manager
  reg dd_reset = 1'b1;
  reg load_req = 1'b0;
  savestate_manager u_mgr (
    .clk(clk_sys),
    .reset(dd_reset),
    .request_save(1'b0),
    .request_load(load_req),
    .allow_save_state(1'b1),
    .cpu_type(tb_current_cpu),
    .cpu_frozen(cpu_frozen),
    .stall(mgr_stall),
    .machine_ce(mgr_machine_ce),
    .busy(ss_busy),
    .done(ss_done),
    .error(ss_error),
    .error_code(ss_error_code),
    .locked_cpu_type(ss_locked_cpu),
    .ss_addr(mgr_ss_addr),
    .ss_wdata(mgr_ss_wdata),
    .ss_wren(mgr_ss_wren),
    .ss_rdata(ss_rdata_mux),
    .ram_bank(mgr_ram_bank),
    .ram_addr(mgr_ram_addr),
    .ram_rd(mgr_ram_rd),
    .ram_wr(mgr_ram_wr),
    .ram_wdata(mgr_ram_wdata),
    .ram_rdata(mgr_ram_rdata),
    .slot_addr(sl_addr),
    .slot_rd(sl_rd),
    .slot_wr(sl_wr),
    .slot_wdata(sl_wdata),
    .slot_rdata(sl_rdata),
    .slot_ready(sl_ready)
  );

  // ---------------------------------------------------------------- slot memory
  // 128 KiB, preloaded from the file; protocol-TB 2-cycle latency model.
  reg [63:0] slots [0:STATE_WORDS-1];
  reg        sl_ready;
  reg        pending, pending_read, cooldown;
  reg [14:0] pending_addr;
  reg [63:0] pending_wdata;
  reg [2:0]  delay_count;

  initial begin
    for (int i = 0; i < STATE_WORDS; i = i + 1)
      slots[i] = {file_bytes[i*8+7], file_bytes[i*8+6], file_bytes[i*8+5], file_bytes[i*8+4],
                  file_bytes[i*8+3], file_bytes[i*8+2], file_bytes[i*8+1], file_bytes[i*8]};
  end

  always @(posedge clk_sys) begin
    if (dd_reset) begin
      pending <= 1'b0; cooldown <= 1'b0; sl_ready <= 1'b0;
    end else begin
      sl_ready <= 1'b0;
      if (cooldown) begin
        // one-cycle gap: the manager still drives the word it just got ready
        // for while it advances - do not re-latch (protocol-TB guard)
        cooldown <= 1'b0;
      end else if (!pending && (sl_rd || sl_wr)) begin
        pending <= 1'b1;
        pending_read <= sl_rd;
        pending_addr <= sl_addr;
        pending_wdata <= sl_wdata;
        delay_count <= 3'd2;
      end else if (pending) begin
        if (delay_count != 0)
          delay_count <= delay_count - 1'b1;
        else begin
          pending <= 1'b0;
          cooldown <= 1'b1;
          sl_ready <= 1'b1;
          if (pending_read)
            sl_rdata <= slots[pending_addr];
          else
            slots[pending_addr] <= pending_wdata;
        end
      end
    end
  end

  // ---------------------------------------------------------------- reference words
  function automatic [63:0] file_word(input int w);
    file_word = {file_bytes[w*8+7], file_bytes[w*8+6], file_bytes[w*8+5], file_bytes[w*8+4],
                 file_bytes[w*8+3], file_bytes[w*8+2], file_bytes[w*8+1], file_bytes[w*8]};
  endfunction
  function automatic [7:0] file_byte(input int f);
    file_byte = file_bytes[f];
  endfunction

  // ---------------------------------------------------------------- monitors
  integer hs_rises = 0;
  integer ram_writes = 0;
  always @(posedge hsync) hs_rises = hs_rises + 1;
  always @(posedge clk_sys) if (ram_we) ram_writes = ram_writes + 1;

  // ---------------------------------------------------------------- checks
  integer fails = 0;

  task automatic probe_ram(input [15:0] bank_addr, input logic is_aux, input int file_off);
    logic [7:0] got;
    @(posedge clk_sys);
    tb_probe <= 1'b1; tb_probe_addr <= bank_addr;
    repeat (2) @(posedge clk_sys);
    got = is_aux ? aux_qb : main_qb;
    tb_probe <= 1'b0;
    if (got !== file_byte(file_off)) begin
      $display("FAIL C2 ram sample: %s[%05h] = %02x, file byte %0d = %02x",
        is_aux ? "aux" : "main", bank_addr, got, file_off, file_byte(file_off));
      fails = fails + 1;
    end
  endtask

  task automatic probe_reg(input int i, input logic [63:0] exp_word);
    logic [63:0] got;
    @(posedge clk_sys);
    tb_ss_probe_addr <= i[9:0];
    repeat (2) @(posedge clk_sys);
    got = ss_rdata_mux;
    if (got !== exp_word) begin
      $display("FAIL C3 reg word %0d: got %016h, file word %0d = %016h",
        i, got, 16 + i, exp_word);
      fails = fails + 1;
    end
  endtask

  // ---------------------------------------------------------------- main
  initial begin
    // cold boot
    repeat (100) @(posedge clk_sys);
    dd_reset <= 1'b0;
    repeat (2000) @(posedge clk_sys);   // let the machine settle

    // issue the load (1-cycle pulse, as savestate_ui/hotkeys do)
    @(negedge clk_sys);
    load_req <= 1'b1;
    @(negedge clk_sys);
    load_req <= 1'b0;

    // wait for done with timeout
    fork
      begin : wait_done
        wait (ss_done);
        disable fork;
      end
      begin : timeout
        repeat (2_000_000) @(posedge clk_sys);
        $display("FAIL C1: no ss_done within 2M clk_sys after request_load");
        fails = fails + 1;
        disable fork;
      end
    join
    if (ss_error) begin
      $display("FAIL C1: load done with error=1 error_code=%0d", ss_error_code);
      fails = fails + 1;
    end else begin
      $display("PASS C1: load done, no error (locked_cpu=%0b)", ss_locked_cpu);
    end
    repeat (20) @(posedge clk_sys);

    // C2: RAM sample match (24 main + 24 aux, strided; per-sample failures
    // already increment fails)
    begin : c2
      logic [15:0] a_main, a_aux;
      for (int s = 0; s < 24; s = s + 1) begin
        a_main = 16'(s * 1024 + 123);
        a_aux  = 16'(s * 1024 + 77);
        probe_ram(a_main, 1'b0, 256 + int'(a_main));
        probe_ram(a_aux,  1'b1, 256 + 65536 + int'(a_aux));
      end
      $display("C2: RAM sample probes done (48 samples)");
    end

    // C3: register word readback (ss_addr 0..10 vs file words 16..26)
    for (int i = 0; i < 11; i = i + 1)
      probe_reg(i, file_word(16 + i));
    $display("C3: register word readbacks done (11 words)");

    // C4: liveness - run a while after the load
    repeat (500_000) @(posedge clk_sys);
    if (cpu_frozen) begin
      $display("FAIL C4: cpu_frozen still high after resume");
      fails = fails + 1;
    end
    if (hs_rises < 10) begin
      $display("FAIL C4: hsync rises=%0d < 10 - video pipeline not running", hs_rises);
      fails = fails + 1;
    end
    if (ram_writes == 0) begin
      $display("FAIL C4: no RAM writes after resume - machine not executing");
      fails = fails + 1;
    end
    if (fails == 0)
      $display("PASS C4: machine alive (hs_rises=%0d, ram_writes=%0d, cpu_frozen=%0b)",
        hs_rises, ram_writes, cpu_frozen);

    // ---------------------------------------------------------------- report
    $display("summary: fails=%0d", fails);
    if (fails == 0) $display("ALL CHECKS PASS");
    $finish;
  end

  // watchdog: hard-stop if something wedges before $finish
  initial begin
    repeat (200_000_000) @(posedge clk_sys);
    $display("FAIL: watchdog - simulation hung (200M clk_sys)");
    $finish;
  end

endmodule
