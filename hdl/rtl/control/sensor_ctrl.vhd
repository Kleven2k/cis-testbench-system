library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sensor_ctrl is
    generic (
        GRID_COLS : integer := 8;
        GRID_ROWS : integer := 8
    );
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        start          : in  std_logic;
        read_mode      : in  std_logic;

        delay_time       : in unsigned(15 downto 0); -- exposure time (us)
        cds_delay_us     : in unsigned(7 downto 0);  -- CDS window (us)
        reset_us         : in unsigned(7 downto 0);  -- reset hold (us)
        pixel_dwell_time : in unsigned(15 downto 0); -- dwell time per pixel (us)
        cds_enable       : in std_logic;
        photosense_mode  : in std_logic;             -- 1 = skip alternate pixels in READOUT

        -- Runtime grid size (must be <= GRID_COLS/GRID_ROWS)
        active_cols      : in integer range 1 to 64;
        active_rows      : in integer range 1 to 64;

        done           : out std_logic;
        exposure_done  : out std_logic;
        cds_done       : out std_logic;
        single_done    : out std_logic;

        nRES           : out std_logic;
        nTX            : out std_logic;
        AX             : out std_logic_vector(2 downto 0);
        AY             : out std_logic_vector(2 downto 0);

        px             : out std_logic_vector(2 downto 0);
        py             : out std_logic_vector(2 downto 0);

        px_select      : in  std_logic_vector(2 downto 0);
        py_select      : in  std_logic_vector(2 downto 0);

        pixel_index    : out std_logic_vector(5 downto 0); -- 0..PIXEL_COUNT-1
        pixel_step     : out std_logic;                    -- 1-cycle pulse at end of dwell

        idle_state       : out std_logic;
        reset_state      : out std_logic;
        cds_state        : out std_logic;
        exposure_state   : out std_logic;
        readout_state    : out std_logic;
        single_pix_state : out std_logic
    );
end sensor_ctrl;

architecture arch of sensor_ctrl is

    constant CLK_FREQ_HZ   : integer := 74_250_000;
    constant CYCLES_PER_US : integer := CLK_FREQ_HZ / 1_000_000;  -- 74

    type state_type is (IDLE, RESET, CDS, INTEGRATE, READOUT, SINGLE_PIXEL);
    signal state, next_state : state_type := IDLE;

    signal cds_counter, exposure_counter : integer := 0;
    signal cds_limit_cycles              : integer;

    signal nres_reg, ntx_reg             : std_logic := '1';
    signal done_reg,
           cds_done_reg,
           exposure_done_reg,
           single_done_reg               : std_logic := '0';

    signal ax_reg, ay_reg                : std_logic_vector(2 downto 0) := (others => '0');
    signal px_reg, py_reg                : std_logic_vector(2 downto 0) := (others => '0');

    signal reset_limit_cycles            : integer;
    signal reset_counter                 : integer := 0;

    constant PIXEL_COUNT                 : integer := GRID_COLS * GRID_ROWS;
    signal pixel_counter                 : integer range 0 to PIXEL_COUNT - 1 := 0;

    signal pixel_dwell_counter           : integer := 0;
    signal pixel_step_reg                : std_logic := '0';

    signal exposure_limit_latched        : integer := 0;
    signal pixel_dwell_latched           : integer := 0;

    -- Runtime pixel count derived from active_cols/active_rows inputs.
    signal active_pixel_count : integer range 1 to PIXEL_COUNT;

    -- Alternate-pixel detection using runtime active_cols.
    signal skip_col  : integer range 0 to GRID_COLS - 1;
    signal skip_row  : integer range 0 to GRID_ROWS - 1;
    signal skip_pos  : std_logic;

begin

    active_pixel_count <= active_cols * active_rows;

    skip_col <= pixel_counter mod active_cols;
    skip_row <= pixel_counter / active_cols;
    skip_pos <= '1' when ((skip_col + skip_row) mod 2 = 0) else '0';

    cds_limit_cycles   <= to_integer(cds_delay_us) * CYCLES_PER_US;
    reset_limit_cycles <= to_integer(reset_us)     * CYCLES_PER_US;

    nRES          <= nres_reg;
    nTX           <= ntx_reg;

    done          <= done_reg;
    cds_done      <= cds_done_reg;
    exposure_done <= exposure_done_reg;
    single_done   <= single_done_reg;

    AX <= px_reg when (state = SINGLE_PIXEL) else ax_reg;
    AY <= py_reg when (state = SINGLE_PIXEL) else ay_reg;
    px <= px_reg;
    py <= py_reg;

    pixel_index <= std_logic_vector(to_unsigned(pixel_counter, 6));
    pixel_step  <= pixel_step_reg;

    idle_state       <= '1' when state = IDLE         else '0';
    reset_state      <= '1' when state = RESET        else '0';
    cds_state        <= '1' when state = CDS          else '0';
    exposure_state   <= '1' when state = INTEGRATE    else '0';
    readout_state    <= '1' when state = READOUT      else '0';
    single_pix_state <= '1' when state = SINGLE_PIXEL else '0';

    process(clk, rst)
    begin
        if rst = '1' then
            state             <= IDLE;
            exposure_counter  <= 0;
            cds_counter       <= 0;
            reset_counter     <= 0;
            pixel_counter     <= 0;
            nres_reg          <= '1';
            ntx_reg           <= '1';
            done_reg          <= '0';
            pixel_step_reg    <= '0';
            exposure_done_reg <= '0';
            cds_done_reg      <= '0';
            single_done_reg   <= '0';

        elsif rising_edge(clk) then
            state    <= next_state;
            nres_reg <= '1';
            ntx_reg  <= '1';
            done_reg <= '0';

            -- Latch timing parameters on leaving RESET
            if state = RESET and next_state /= RESET then
                exposure_counter       <= 0;
                exposure_done_reg      <= '0';
                cds_done_reg          <= '0';
                exposure_limit_latched <= to_integer(delay_time)       * CYCLES_PER_US;
                pixel_dwell_latched    <= to_integer(pixel_dwell_time)  * CYCLES_PER_US;
            end if;

            -- Initialise on entering READOUT
            if state /= READOUT and next_state = READOUT then
                pixel_counter       <= 0;
                pixel_dwell_counter <= 0;
                pixel_step_reg      <= '0';
                ax_reg              <= (others => '0');
                ay_reg              <= (others => '0');
            end if;

            -- Initialise on entering SINGLE_PIXEL
            if state /= SINGLE_PIXEL and next_state = SINGLE_PIXEL then
                pixel_dwell_counter <= 0;
                single_done_reg     <= '0';
                px_reg              <= (others => '0');
                py_reg              <= (others => '0');
            end if;

            case state is

                when IDLE =>
                    cds_counter         <= 0;
                    pixel_counter       <= 0;
                    reset_counter       <= 0;
                    pixel_dwell_counter <= 0;
                    single_done_reg     <= '0';

                when RESET =>
                    nres_reg            <= '0';
                    ntx_reg             <= '0';
                    cds_counter         <= 0;
                    pixel_dwell_counter <= 0;

                    if reset_counter < reset_limit_cycles then
                        reset_counter <= reset_counter + 1;
                    else
                        reset_counter <= 0;
                    end if;

                when CDS =>
                    if cds_counter < cds_limit_cycles then
                        cds_counter <= cds_counter + 1;
                    else
                        cds_done_reg <= '1';
                    end if;

                when INTEGRATE =>
                    ntx_reg <= '0';   -- transfer gate LOW for entire exposure

                    if exposure_done_reg = '0' then
                        if exposure_counter < exposure_limit_latched then
                            exposure_counter <= exposure_counter + 1;
                        else
                            exposure_done_reg <= '1';
                        end if;
                    end if;

                when READOUT =>
                    cds_done_reg      <= '0';
                    exposure_done_reg <= '0';
                    pixel_step_reg    <= '0';

                    -- When photosense_mode is active, skip alternate pixels.
                    if photosense_mode = '1' and skip_pos = '1' then
                        if pixel_counter < active_pixel_count - 1 then
                            pixel_counter <= pixel_counter + 1;
                        else
                            pixel_counter <= 0;
                            done_reg      <= '1';
                        end if;
                        pixel_dwell_counter <= 0;
                    else
                        ax_reg <= std_logic_vector(to_unsigned(pixel_counter mod active_cols, 3));
                        ay_reg <= std_logic_vector(to_unsigned(pixel_counter / active_cols, 3));

                        if pixel_dwell_counter < pixel_dwell_latched - 1 then
                            pixel_dwell_counter <= pixel_dwell_counter + 1;
                        else
                            pixel_dwell_counter <= 0;
                            pixel_step_reg      <= '1';

                            if pixel_counter < active_pixel_count - 1 then
                                pixel_counter <= pixel_counter + 1;
                            else
                                pixel_counter <= 0;
                                done_reg      <= '1';
                            end if;
                        end if;
                    end if;

                when SINGLE_PIXEL =>
                    px_reg          <= px_select;
                    py_reg          <= py_select;
                    single_done_reg <= '0';

                    if pixel_dwell_counter < pixel_dwell_latched then
                        pixel_dwell_counter <= pixel_dwell_counter + 1;
                    else
                        pixel_dwell_counter <= 0;
                        single_done_reg     <= '1';
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;

    process(state, start, cds_done_reg, cds_enable,
            exposure_done_reg, single_done_reg, done_reg,
            read_mode, reset_counter, reset_limit_cycles)
    begin
        case state is
            when IDLE =>
                if start = '1' then
                    next_state <= RESET;
                else
                    next_state <= IDLE;
                end if;

            when RESET =>
                if reset_counter = reset_limit_cycles then
                    if cds_enable = '1' then
                        next_state <= CDS;
                    else
                        next_state <= INTEGRATE;
                    end if;
                else
                    next_state <= RESET;
                end if;

            when CDS =>
                if cds_done_reg = '1' then
                    next_state <= INTEGRATE;
                else
                    next_state <= CDS;
                end if;

            when INTEGRATE =>
                if exposure_done_reg = '1' then
                    if read_mode = '1' then
                        next_state <= SINGLE_PIXEL;
                    else
                        next_state <= READOUT;
                    end if;
                else
                    next_state <= INTEGRATE;
                end if;

            when READOUT =>
                if done_reg = '1' then
                    next_state <= RESET;
                else
                    next_state <= READOUT;
                end if;

            when SINGLE_PIXEL =>
                if single_done_reg = '1' then
                    next_state <= RESET;
                else
                    next_state <= SINGLE_PIXEL;
                end if;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

end arch;
