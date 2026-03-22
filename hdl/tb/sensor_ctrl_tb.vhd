library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sensor_ctrl_tb is
end sensor_ctrl_tb;

architecture rtl of sensor_ctrl_tb is

    -- Component under test
    component sensor_ctrl is
        Port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            start          : in  std_logic;
            read_mode      : in  std_logic;  -- choose the either full-frame or single-pixel mode
            delay_time     : in unsigned(15 downto 0);
            cds_delay_time : in unsigned(15 downto 0);
            --done_delay     : in integer;

            -- Done signals
            done           : out std_logic;
            exposure_done  : out std_logic;
            cds_done       : out std_logic;
            single_done    : out std_logic;


            nRES           : out std_logic;
            nTX            : out std_logic;
            AX             : out std_logic_vector(2 downto 0);
            AY             : out std_logic_vector(2 downto 0);

            -- Single-Pixel mode
            px             : out std_logic_vector(2 downto 0);  -- single pixel 
            py             : out std_logic_vector(2 downto 0);  -- single pixel
            px_select      : in  std_logic_vector(2 downto 0);
            py_select      : in  std_logic_vector(2 downto 0);

            -- Debug signals
            idle_state        : out std_logic;
            reset_state       : out std_logic;
            exposure_state    : out std_logic; 
            readout_state     : out std_logic;
            single_pix_state  : out std_logic
        );
    end component;

    -- Signals to connect to DUT
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal start          : std_logic := '0';
    signal read_mode      : std_logic := '0';
    signal delay_time     : unsigned(15 downto 0) := to_unsigned(3, 16);
    signal cds_delay_time : unsigned(15 downto 0) := to_unsigned(2, 16);
    --signal done_delay     : integer := 2;
    signal done           : std_logic;
    signal exposure_done  : std_logic;
    signal cds_done       : std_logic;
    signal single_done    : std_logic;
    signal nRES           : std_logic;
    signal nTX            : std_logic;
    signal AX             : std_logic_vector(2 downto 0);
    signal AY             : std_logic_vector(2 downto 0);
    signal px             : std_logic_vector(2 downto 0);
    signal py             : std_logic_vector(2 downto 0);
    signal px_select      : std_logic_vector(2 downto 0);
    signal py_select      : std_logic_vector(2 downto 0);

    signal idle_state     : std_logic;
    signal reset_state    : std_logic;
    signal exposure_state : std_logic;
    signal readout_state  : std_logic;
    signal single_pix_state : std_logic;

begin

    -- Clock generation: 100 MHz
    clk <= not clk after 5 ns;

    -- Instantiate DUT
    uut: sensor_ctrl
        port map (
            clk        => clk,
            rst        => rst,
            start      => start,
            read_mode  => read_mode,
            delay_time => delay_time,
            cds_delay_time => cds_delay_time,
            done       => done,
            --done_delay => done_delay,
            exposure_done => exposure_done,
            cds_done => cds_done,
            single_done => single_done,
            nRES       => nRES,
            nTX        => nTX,
            AX         => AX,
            AY         => AY,
            px         => px,
            py         => py,
            px_select  => px_select,
            py_select  => py_select,

            -- Debug
            idle_state => idle_state,
            reset_state => reset_state,
            exposure_state => exposure_state,
            readout_state => readout_state,
            single_pix_state => single_pix_state
        );

    -- Test process
    stim_proc: process
    begin
        -- Apply reset
        wait for 20 ns;
        rst <= '0';
        wait for 10 ns;

        -----------------------------------------------------------------------------
        -- Full-Frame Read Mode
        -----------------------------------------------------------------------------
        read_mode <= '0';   -- Full-frame mode
        -- Start sensor control
        start <= '1';
        wait for 10 ns;
        start <= '0';  -- Pulse only once

        -- Wait for the done signal to go high
        wait until done = '1';
        report "Full-frame mode: EXPOSURE complete, READOUT started.";

        --Observe full 64-pixel readout (AX, AY);
        for i in 0 to 63 loop 
            wait until rising_edge(clk);
            report "Reading pixel AX=" & integer'image(to_integer(unsigned(AX))) & 
                   "AY=" & integer'image(to_integer(unsigned(AY)));
        end loop;

        wait for 100 ns; 
        
        --rst <= '1';
        wait for 20 ns;
        --rst <= '0';
        wait for 10 ns;
        -----------------------------------------------------------------------------
        -- Single-Pixel Read Mode
        -----------------------------------------------------------------------------
        read_mode <= '1';   -- Single-pixel mode
        px_select <= std_logic_vector(to_unsigned(2, 3));  -- Select px=2
        py_select <= std_logic_vector(to_unsigned(6, 3));  -- Select py=6

        wait for 20 ns;
        start <= '1'; 
        wait for 10 ns;
        start <= '0';

        wait until single_done = '1';
        report "Single-pixel mode: Read complete.";

        report "Selected Pixel:";
        report "px = " & integer'image(to_integer(unsigned(px)));
        report "py = " & integer'image(to_integer(unsigned(py)));
        report "px_select = " & integer'image(to_integer(unsigned(px_select)));
        report "py_select = " & integer'image(to_integer(unsigned(py_select)));

        wait for 200 ns;
    
        px_select <= std_logic_vector(to_unsigned(1, 3));  -- Select px=1
        py_select <= std_logic_vector(to_unsigned(7, 3));  -- Select py=7

        wait until single_done = '1';
        report "Single-pixel mode: Read complete.";

        report "Selected Pixel:";
        report "px = " & integer'image(to_integer(unsigned(px)));
        report "py = " & integer'image(to_integer(unsigned(py)));
        report "px_select = " & integer'image(to_integer(unsigned(px_select)));
        report "py_select = " & integer'image(to_integer(unsigned(py_select)));

        wait for 200 ns;
        
        px_select <= std_logic_vector(to_unsigned(4, 3));  -- Select px=1
        py_select <= std_logic_vector(to_unsigned(5, 3));  -- Select py=7

        wait until single_done = '1';
        report "Single-pixel mode: Read complete.";

        report "Selected Pixel:";
        report "px = " & integer'image(to_integer(unsigned(px)));
        report "py = " & integer'image(to_integer(unsigned(py)));
        report "px_select = " & integer'image(to_integer(unsigned(px_select)));
        report "py_select = " & integer'image(to_integer(unsigned(py_select)));


        -- Stop simulation
        report "Simulation completed.";
        wait;
    end process;

end rtl;
