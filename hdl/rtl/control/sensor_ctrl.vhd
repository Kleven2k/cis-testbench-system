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

    -- Alternate-pixel detection: pixel is "type A" when (col + row) is even.
    -- For an 8-column grid col = pixel_counter mod 8 = bits [2:0],
    -- row = pixel_counter / 8 = bits [5:3].  LSBs equal → even sum.
    signal pixel_slv : unsigned(5 downto 0);
    signal skip_pos  : std_logic;  -- '1' when current pixel should be skipped

begin

    pixel_slv <= to_unsigned(pixel_counter, 6);
    skip_pos  <= '1' when (pixel_slv(0) = pixel_slv(3)) else '0';

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

                    -- When photosense_mode is active, skip alternate pixels
                    -- (those where col+row is even) to read only one pixel type.
                    if photosense_mode = '1' and skip_pos = '1' then
                        if pixel_counter < PIXEL_COUNT - 1 then
                            pixel_counter <= pixel_counter + 1;
                        else
                            pixel_counter <= 0;
                            done_reg      <= '1';
                        end if;
                        pixel_dwell_counter <= 0;
                    else
                        ax_reg <= std_logic_vector(to_unsigned(pixel_counter mod GRID_COLS, 3));
                        ay_reg <= std_logic_vector(to_unsigned(pixel_counter / GRID_COLS, 3));

                        if pixel_dwell_counter < pixel_dwell_latched - 1 then
                            pixel_dwell_counter <= pixel_dwell_counter + 1;
                        else
                            pixel_dwell_counter <= 0;
                            pixel_step_reg      <= '1';

                            if pixel_counter < PIXEL_COUNT - 1 then
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
            read_mode, reset_counter)
    begin
        case state is
            when IDLE =>
                next_state <= RESET when start = '1' else IDLE;

            when RESET =>
                if reset_counter = reset_limit_cycles then
                    next_state <= CDS when cds_enable = '1' else INTEGRATE;
                else
                    next_state <= RESET;
                end if;

            when CDS =>
                next_state <= INTEGRATE when cds_done_reg = '1' else CDS;

            when INTEGRATE =>
                if exposure_done_reg = '1' then
                    next_state <= SINGLE_PIXEL when read_mode = '1' else READOUT;
                else
                    next_state <= INTEGRATE;
                end if;

            when READOUT =>
                next_state <= RESET when done_reg = '1' else READOUT;

            when SINGLE_PIXEL =>
                next_state <= RESET when single_done_reg = '1' else SINGLE_PIXEL;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

end arch;
