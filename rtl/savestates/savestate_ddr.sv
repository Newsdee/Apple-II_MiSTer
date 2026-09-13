module savestate_ddr #(
  parameter [28:0] BASE_ADDR = 29'd0
) (
  input  wire        clk,
  input  wire        reset,
  input  wire [14:0] slot_addr,
  input  wire [1:0]  slot_sel,   // selected slot; 2 MiB (0x40000 beats) stride
  input  wire        slot_rd,
  input  wire        slot_wr,
  input  wire [63:0] slot_wdata,
  output reg  [63:0] slot_rdata,
  output reg         slot_ready,

  output wire        ddram_clk,
  input  wire        ddram_busy,
  output wire [7:0]  ddram_burstcnt,
  output wire [28:0] ddram_addr,
  input  wire [63:0] ddram_dout,
  input  wire        ddram_dout_ready,
  output reg         ddram_rd,
  output reg  [63:0] ddram_din,
  output wire [7:0]  ddram_be,
  output reg         ddram_we
);
  localparam [2:0] IDLE       = 3'd0;
  localparam [2:0] READ_ISSUE = 3'd1;
  localparam [2:0] READ_WAIT  = 3'd2;
  localparam [2:0] WRITE_WAIT = 3'd3;
  localparam [2:0] COOLDOWN   = 3'd4;

  reg [2:0] state;
  reg [28:0] address_latched;

  // Slot base within the advertised SS3E000000:200000 region:
  // 2 MiB per slot (= ss_size, 0x40000 64-bit beats); the 4 slots exactly
  // fill the 8 MiB region. The 30-bit intermediate keeps the add lint-clean;
  // the sum always fits the 29-bit DDRAM address space.
  wire [29:0] slot_base_ext = {1'b0, BASE_ADDR} + {1'b0, slot_sel, 18'd0};
  wire [28:0] slot_base = slot_base_ext[28:0];

  assign ddram_clk = clk;
  assign ddram_burstcnt = 8'd1;
  assign ddram_addr = address_latched;
  assign ddram_be = 8'hFF;

  // DDRAM request protocol: issue the command, hold it across any
  // waitstates, then RELEASE it on the acceptance cycle and track data
  // (reads) / commit (writes) separately.
  //
  // The ddram_* ports reach the raw cyclonev_hps_interface_fpga2sdram
  // Avalon-MM slave behind a pass-through safe terminator (sysmem ram1).
  // That slave is a level-sampling Avalon-MM port: it accepts a request
  // on every cycle the request is high while waitrequest (ddram_busy)
  // is low. A request must therefore be held only while waitrequest is
  // high (waitstates) and MUST be released on the first low cycle (the
  // acceptance edge). Holding a READ request past acceptance - e.g.
  // until ddram_dout_ready - makes the slave enqueue duplicate reads of
  // the same address; those stale beats then drain ahead of the next
  // request and shift the header beats (word 0 delivered as word 1),
  // which is the hardware "save succeeds, load reports Invalid or
  // empty state" failure.
  //
  // The proven sys client ddr_svc.sv does exactly this: it asserts
  // ram_read for the accepted cycle, holds it across waitstates, and
  // deasserts it on the acceptance cycle (ram_read <= 0 runs on every
  // !ram_waitrequest cycle), then waits for ram_read_ready separately.
  // The write path below already releases ddram_we on acceptance; the
  // read path is now aligned to the same protocol.
  always @(posedge clk) begin
    slot_ready <= 1'b0;

    if (reset) begin
      state <= IDLE;
      address_latched <= 29'd0;
      slot_rdata <= 64'd0;
      ddram_din <= 64'd0;
      ddram_rd <= 1'b0;
      ddram_we <= 1'b0;
    end
    else begin
      case (state)
        IDLE: begin
          // Issue only when the slave can accept; the request is then
          // held (rd/we stay high) across waitstates and released on the
          // acceptance cycle (READ_ISSUE / WRITE_WAIT handle that).
          if (!ddram_busy && slot_rd) begin
            address_latched <= slot_base + {14'd0, slot_addr};
            ddram_rd <= 1'b1;
            state <= READ_ISSUE;
          end
          else if (!ddram_busy && slot_wr) begin
            address_latched <= slot_base + {14'd0, slot_addr};
            ddram_din <= slot_wdata;
            ddram_we <= 1'b1;
            state <= WRITE_WAIT;
          end
        end
        READ_ISSUE: begin
          // ddram_rd is asserted. Hold it across waitstates; on the first
          // !ddram_busy cycle the slave accepts the read (acceptance edge),
          // so release it there and move on to wait for the data.
          if (!ddram_busy) begin
            ddram_rd <= 1'b0;
            state <= READ_WAIT;
          end
        end
        READ_WAIT: begin
          // ddram_rd is already released (deasserted at acceptance); the
          // slave delivers the beat independently via ddram_dout_ready.
          // Releasing at acceptance is safe: an accepted read cannot be
          // cancelled, and deasserting now prevents duplicate re-accept.
          if (ddram_dout_ready) begin
            slot_rdata <= ddram_dout;
            slot_ready <= 1'b1;
            state <= COOLDOWN;
          end
        end
        WRITE_WAIT: begin
          // Hold the write request until the slave commits the beat
          // (waitrequest deasserted); releasing earlier would lose it.
          if (!ddram_busy) begin
            ddram_we <= 1'b0;
            slot_ready <= 1'b1;
            state <= COOLDOWN;
          end
        end
        COOLDOWN: state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
