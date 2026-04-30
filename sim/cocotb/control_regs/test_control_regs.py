"""
cocotb tests for control_regs.

Tests the register file, dual control mode (local buttons vs remote UART),
start pulse edge detection, and mode output signals.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 13  # ~74.25 MHz (close enough for register logic)


async def reset_dut(dut):
    dut.rst.value          = 1
    dut.delay_up.value     = 0
    dut.delay_down.value   = 0
    dut.dwell_up.value     = 0
    dut.dwell_down.value   = 0
    dut.start_btn.value    = 0
    dut.sw_read_mode.value = 0
    dut.sw_cds_enable.value = 0
    dut.uart_write_en.value = 0
    dut.uart_addr.value    = 0
    dut.uart_data.value    = 0
    dut.read_addr.value    = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def uart_write(dut, addr, data):
    """Write one byte to the register file via the UART write interface."""
    await RisingEdge(dut.clk)
    dut.uart_addr.value    = addr
    dut.uart_data.value    = data
    dut.uart_write_en.value = 1
    await RisingEdge(dut.clk)
    dut.uart_write_en.value = 0


async def enable_remote_mode(dut):
    """Set remote_mode bit (CTRL[7]) via UART — always writable."""
    await uart_write(dut, 0x00, 0x80)
    await ClockCycles(dut.clk, 2)


async def pulse(dut, signal):
    """Assert a signal high for one clock cycle."""
    await RisingEdge(dut.clk)
    signal.value = 1
    await RisingEdge(dut.clk)
    signal.value = 0


# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_defaults(dut):
    """After reset, exposure=100, dwell=100, reset_us=10, cds_delay=2."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await ClockCycles(dut.clk, 2)
    assert int(dut.exposure_us.value)  == 100, f"exposure_us={int(dut.exposure_us.value)}"
    assert int(dut.dwell_us.value)     == 100, f"dwell_us={int(dut.dwell_us.value)}"
    assert int(dut.reset_us.value)     == 10,  f"reset_us={int(dut.reset_us.value)}"
    assert int(dut.cds_delay_us.value) == 2,   f"cds_delay_us={int(dut.cds_delay_us.value)}"
    dut._log.info("Reset defaults — OK")


@cocotb.test()
async def test_remote_mode_write_registers(dut):
    """In remote mode, UART writes update exposure and dwell registers."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await enable_remote_mode(dut)

    # Write exposure = 0x01F4 = 500 µs
    await uart_write(dut, 0x01, 0xF4)  # low byte
    await uart_write(dut, 0x02, 0x01)  # high byte
    await ClockCycles(dut.clk, 3)
    assert int(dut.exposure_us.value) == 500, \
        f"exposure_us expected 500 got {int(dut.exposure_us.value)}"

    # Write dwell = 0x012C = 300 µs
    await uart_write(dut, 0x03, 0x2C)
    await uart_write(dut, 0x04, 0x01)
    await ClockCycles(dut.clk, 3)
    assert int(dut.dwell_us.value) == 300, \
        f"dwell_us expected 300 got {int(dut.dwell_us.value)}"

    dut._log.info("Remote mode register writes — OK")


@cocotb.test()
async def test_local_mode_buttons_ignored_in_remote(dut):
    """In remote mode, button presses do not change exposure_us."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await enable_remote_mode(dut)

    # Set exposure to known value via UART
    await uart_write(dut, 0x01, 0x64)  # 100
    await uart_write(dut, 0x02, 0x00)
    await ClockCycles(dut.clk, 3)

    before = int(dut.exposure_us.value)
    await pulse(dut, dut.delay_up)
    await ClockCycles(dut.clk, 3)
    after = int(dut.exposure_us.value)

    assert before == after, \
        f"Button changed exposure in remote mode: {before} -> {after}"
    dut._log.info("Buttons ignored in remote mode — OK")


@cocotb.test()
async def test_local_mode_delay_up(dut):
    """In local mode, delay_up increments exposure_us by 10."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)  # local mode, exposure starts at 100

    before = int(dut.exposure_us.value)
    await pulse(dut, dut.delay_up)
    await ClockCycles(dut.clk, 2)
    after = int(dut.exposure_us.value)

    assert after == before + 10, f"delay_up: expected {before+10} got {after}"
    dut._log.info(f"delay_up: {before} -> {after} — OK")


@cocotb.test()
async def test_local_mode_delay_down(dut):
    """In local mode, delay_down decrements exposure_us by 10."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    before = int(dut.exposure_us.value)
    await pulse(dut, dut.delay_down)
    await ClockCycles(dut.clk, 2)
    after = int(dut.exposure_us.value)

    assert after == before - 10, f"delay_down: expected {before-10} got {after}"
    dut._log.info(f"delay_down: {before} -> {after} — OK")


@cocotb.test()
async def test_local_mode_switches(dut):
    """In local mode, sw_read_mode and sw_cds_enable pass through directly."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    dut.sw_read_mode.value  = 1
    dut.sw_cds_enable.value = 1
    await ClockCycles(dut.clk, 2)

    assert int(dut.read_mode.value)  == 1, "read_mode should follow sw_read_mode"
    assert int(dut.cds_enable.value) == 1, "cds_enable should follow sw_cds_enable"

    dut.sw_read_mode.value  = 0
    dut.sw_cds_enable.value = 0
    await ClockCycles(dut.clk, 2)

    assert int(dut.read_mode.value)  == 0
    assert int(dut.cds_enable.value) == 0
    dut._log.info("Local mode switches pass-through — OK")


@cocotb.test()
async def test_remote_mode_register_readback(dut):
    """UART read interface returns the value stored in the register file."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await enable_remote_mode(dut)

    await uart_write(dut, 0x06, 0x1E)  # reset_us = 30
    await ClockCycles(dut.clk, 2)

    dut.read_addr.value = 0x06
    await ClockCycles(dut.clk, 1)
    val = int(dut.read_data.value)
    assert val == 0x1E, f"readback reg[6]: expected 0x1E got 0x{val:02X}"
    dut._log.info("Register readback — OK")


@cocotb.test()
async def test_write_blocked_outside_remote_mode(dut):
    """Non-zero register writes are ignored when remote_mode is not set."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)  # remote_mode = 0

    # Try to write EXP_LO without enabling remote mode first
    await uart_write(dut, 0x01, 0xFF)
    await ClockCycles(dut.clk, 3)

    dut.read_addr.value = 0x01
    await ClockCycles(dut.clk, 1)
    val = int(dut.read_data.value)
    assert val == 0x00, f"reg[1] should be 0 without remote mode, got 0x{val:02X}"
    dut._log.info("Write blocked outside remote mode — OK")


@cocotb.test()
async def test_start_pulse_edge_detect(dut):
    """In remote mode, start_pulse fires for exactly one cycle on CTRL[0] 0→1."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await enable_remote_mode(dut)

    # Set start bit
    await uart_write(dut, 0x00, 0x81)  # remote_mode=1, start=1
    await ClockCycles(dut.clk, 2)

    pulse_seen = False
    for _ in range(5):
        await RisingEdge(dut.clk)
        if int(dut.start_pulse.value) == 1:
            pulse_seen = True
            break
    assert pulse_seen, "start_pulse never fired after CTRL[0] set"

    # One cycle later it must be deasserted
    await RisingEdge(dut.clk)
    assert int(dut.start_pulse.value) == 0, "start_pulse stayed high longer than one cycle"
    dut._log.info("start_pulse edge detect — OK")


@cocotb.test()
async def test_soft_reset_remote(dut):
    """soft_reset follows CTRL[1] in remote mode and is 0 in local mode."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    # Local mode — soft_reset must be 0 regardless
    assert int(dut.soft_reset.value) == 0, "soft_reset should be 0 in local mode"

    await enable_remote_mode(dut)
    await uart_write(dut, 0x00, 0x82)  # remote_mode=1, soft_reset=1
    await ClockCycles(dut.clk, 2)
    assert int(dut.soft_reset.value) == 1, "soft_reset should follow CTRL[1] in remote mode"

    await uart_write(dut, 0x00, 0x80)  # clear soft_reset
    await ClockCycles(dut.clk, 2)
    assert int(dut.soft_reset.value) == 0, "soft_reset should clear when CTRL[1]=0"
    dut._log.info("soft_reset remote control — OK")


@cocotb.test()
async def test_mode_register_outputs(dut):
    """MODE register bits map correctly to photosense_mode, disp_gain, invert_pol."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await enable_remote_mode(dut)

    # Write MODE = 0b00011110 = 0x1E:
    #   invert_pol=1 [4], disp_gain=3 [3:2], photosense_mode=1 [1], read_mode=0 [0]
    await uart_write(dut, 0x05, 0x1E)
    await ClockCycles(dut.clk, 3)

    assert int(dut.invert_pol.value)      == 1, f"invert_pol={int(dut.invert_pol.value)}"
    assert int(dut.disp_gain.value)       == 3, f"disp_gain={int(dut.disp_gain.value)}"
    assert int(dut.photosense_mode.value) == 1, f"photosense_mode={int(dut.photosense_mode.value)}"
    assert int(dut.read_mode.value)       == 0, f"read_mode={int(dut.read_mode.value)}"
    dut._log.info("MODE register outputs — OK")
