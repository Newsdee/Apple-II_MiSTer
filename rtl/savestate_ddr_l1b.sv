module savestate_ddr_l1b #(
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
  localparam [1:0] IDLE = 2'd0;
  localparam [1:0] READ_WAIT = 2'd1;
  localparam [1:0] WRITE_WAIT = 2'd2;
  localparam [1:0] COOLDOWN = 2'd3;

  reg [1:0] state;
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

  // DDRAM request protocol: issue only while the slave is ready, then
  // HOLD the request asserted until the transaction is consumed.
  //
  // The ddram_* ports reach the raw cyclonev_hps_interface_fpga2sdram
  // Avalon-MM slave behind a pass-through safe terminator (sysmem ram1).
  // That slave samples a request only while waitrequest (ddram_busy)
  // is low; HPS Linux traffic makes the SDRAM controller stretch
  // waitrequest frequently. A request deasserted one cycle after it was
  // asserted is therefore silently lost (write dropped, read never
  // completes) - exactly the "save succeeds, load reads zeros" failure
  // observed in hardware. The sys' proven SDRAM clients (ddr_svc.sv,
  // ao486 l2_cache.v) all hold ram_rd/ram_we until completion for this
  // reason. Releasing is safe exactly at completion: the slave cannot
  // accept a new request while the current one is pending, so no
  // phantom second transaction is possible.
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
          // held (rd/we stay high) for the rest of the transaction.
          if (!ddram_busy && slot_rd) begin
            address_latched <= slot_base + {14'd0, slot_addr};
            ddram_rd <= 1'b1;
            state <= READ_WAIT;
          end
          else if (!ddram_busy && slot_wr) begin
            address_latched <= slot_base + {14'd0, slot_addr};
            ddram_din <= slot_wdata;
            ddram_we <= 1'b1;
            state <= WRITE_WAIT;
          end
        end
        READ_WAIT: begin
          // Hold the read request until the slave delivers the beat;
          // release on the data-ready cycle (the beat is consumed).
          if (ddram_dout_ready) begin
            slot_rdata <= ddram_dout;
            ddram_rd <= 1'b0;
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
