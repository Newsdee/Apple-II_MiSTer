LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

-- ===========================================================================
-- woz_bram.vhd
--
-- Quartus altsyncram implementation of rtl/woz/woz_bram.sv (the WOZ track
-- buffer).  Drop-in replacement for the Verilog behavioral model, used ONLY
-- if Quartus 17.0.2 fails to infer the Verilog file into block RAM (the
-- dpram.v trap: Error 170011 / LUT-based RAM).  See PLAN.md "Open risk".
--
-- Behavioral contract it must match (woz_bram.sv):
--   * Port A (clock_a): synchronous read/write, REGISTERED output (1-cycle
--     latency), write-first (read-during-write = NEW_DATA):
--         q_a <= wren_a ? data_a : mem[address_a]
--   * Port B (clock_b): synchronous read/write, REGISTERED output (1-cycle
--     latency), write-first (read-during-write = NEW_DATA):
--         q_b <= wren_b ? data_b : mem[address_b]
--   * each port's read and write share the SAME address, so the altsyncram
--     NEW_DATA mode reproduces the write-first mux exactly.
--
-- The Verilog model's init_file parameter is never set (""), so the RAM is
-- power-up zero (power_up_uninitialized = "FALSE"); the generic is kept for
-- parameter-name parity but is unused.
-- ===========================================================================
entity woz_bram is
    generic (
        width_a   : integer := 8;
        widthad_a : integer := 10;
        init_file : string  := ""
    );
    port (
        -- Port A
        clock_a   : in  std_logic;
        wren_a    : in  std_logic;
        address_a : in  std_logic_vector (widthad_a-1 downto 0);
        data_a    : in  std_logic_vector (width_a-1 downto 0);
        q_a       : out std_logic_vector (width_a-1 downto 0);
        -- Port B
        clock_b   : in  std_logic;
        wren_b    : in  std_logic;
        address_b : in  std_logic_vector (widthad_a-1 downto 0);
        data_b    : in  std_logic_vector (width_a-1 downto 0);
        q_b       : out std_logic_vector (width_a-1 downto 0)
    );
end entity woz_bram;

architecture SYN of woz_bram is
    signal clocken_tie : std_logic := '1';
begin
    altsyncram_component : altsyncram
    generic map (
        address_reg_b                  => "BYPASS",
        clock_enable_input_a           => "NORMAL",
        clock_enable_input_b           => "NORMAL",
        clock_enable_output_a          => "BYPASS",
        clock_enable_output_b          => "BYPASS",
        indata_reg_b                   => "BYPASS",
        intended_device_family         => "Cyclone V",
        lpm_type                       => "altsyncram",
        numwords_a                     => 2**widthad_a,
        numwords_b                     => 2**widthad_a,
        operation_mode                 => "BIDIR_DUAL_PORT",
        outdata_aclr_a                 => "NONE",
        outdata_aclr_b                 => "NONE",
        outdata_reg_a                  => "CLOCK0",
        outdata_reg_b                  => "CLOCK1",
        power_up_uninitialized         => "FALSE",
        read_during_write_mode_port_a  => "NEW_DATA_NO_NBE_READ",
        read_during_write_mode_port_b  => "NEW_DATA_NO_NBE_READ",
        widthad_a                      => widthad_a,
        widthad_b                      => widthad_a,
        width_a                        => width_a,
        width_b                        => width_a,
        width_byteena_a                => 1,
        width_byteena_b                => 1,
        wrcontrol_wraddress_reg_b      => "BYPASS"
    )
    port map (
        address_a  => address_a,
        address_b  => address_b,
        clock0     => clock_a,
        clock1     => clock_b,
        clocken0   => clocken_tie,
        clocken1   => clocken_tie,
        data_a     => data_a,
        data_b     => data_b,
        wren_a     => wren_a,
        wren_b     => wren_b,
        q_a        => q_a,
        q_b        => q_b
    );

end architecture SYN;
