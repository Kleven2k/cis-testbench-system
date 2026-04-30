"""
cocotb unit tests for sensor_ctrl FSM.

NOTE: CYCLES_PER_US = 74 and INTER_PIXEL_DELAY_US = 100 are hardcoded
in the RTL. A full-frame scan takes ~480k clock cycles even at minimum
timing values. This is expected — let the simulation run.

Clock: 74.25 MHz -> period ~13.5 ns
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 13.5   # 74.25 MHz pixel clock
CYCLES_PER_US = 74     # matches RTL constant


async def reset_dut(dut, cols=8, rows=8):
    """Apply reset and release."""
    dut.rst.value              = 1
    dut.start.value            = 0
    dut.read_mode.value        = 0
    dut.cds_enable.value       = 0
    dut.delay_time.value       = 0
    dut.cds_delay_us.value     = 0
    dut.reset_us.value         = 0
    dut.pixel_dwell_time.value = 0
    dut.px_select.value        = 0
    dut.py_select.value        = 0
    dut.active_cols.value      = cols
    dut.active_rows.value      = rows
    dut.photosense_mode.value  = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def pulse_start(dut):
    """Single-cycle start pulse."""
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


async def wait_for_signal(dut, signal, timeout_us=50000):
    """Wait for a signal to go high, with timeout. Returns True if signal reached."""
    timeout_cycles = timeout_us * CYCLES_PER_US
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if signal.value == 1:
            return True
    return False


# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_idles(dut):
    """After reset, FSM should be in IDLE."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    assert dut.idle_state.value == 1, "Expected IDLE after reset"
    assert dut.nRES.value       == 1, "nRES should be deasserted in IDLE"
    assert dut.nTX.value        == 1, "nTX should be deasserted in IDLE"


@cocotb.test()
async def test_reset_phase(dut):
    """Start pulse should move FSM into RESET, asserting nRES low."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    dut.reset_us.value         = 2
    dut.delay_time.value       = 1
    dut.pixel_dwell_time.value = 1

    await pulse_start(dut)

    await RisingEdge(dut.clk)
    assert dut.reset_state.value == 1, "Expected RESET state after start"
    assert dut.nRES.value        == 0, "nRES should be asserted (low) in RESET"


@cocotb.test()
async def test_full_frame_scan(dut):
    """
    Full-frame scan: check AX/AY step from (0,0) to (7,7) and done pulses.
    Uses minimum timing values (1 us each).
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    dut.reset_us.value         = 1
    dut.delay_time.value       = 1   # exposure = 1 us
    dut.pixel_dwell_time.value = 1   # dwell = 1 us
    dut.cds_enable.value       = 0
    dut.read_mode.value        = 0   # full frame

    await pulse_start(dut)

    # Wait for READOUT state
    reached = await wait_for_signal(dut, dut.readout_state, timeout_us=10000)
    assert reached, "Timed out waiting for READOUT state"

    # Capture pixel addresses on each pixel_step pulse
    captured = []
    prev_step = 0
    for _ in range(600_000):
        await RisingEdge(dut.clk)

        step = int(dut.pixel_step.value)
        if step == 1 and prev_step == 0:  # rising edge of pixel_step
            ax = int(dut.AX.value)
            ay = int(dut.AY.value)
            captured.append((ax, ay))
        prev_step = step

        if dut.done.value == 1:
            break

    cols = int(dut.active_cols.value)
    rows = int(dut.active_rows.value)
    expected_count = cols * rows

    assert dut.done.value == 1, "done never asserted — scan did not complete"
    assert len(captured) == expected_count, \
        f"Expected {expected_count} pixel steps, got {len(captured)}"

    # Verify AX increments 0..(cols-1), AY increments every cols
    expected = [(ax, ay) for ay in range(rows) for ax in range(cols)]
    assert captured == expected, f"Address sequence mismatch:\n{captured}"

    dut._log.info(f"Full-frame scan complete — {len(captured)} pixels captured")


@cocotb.test()
async def test_cds_phase(dut):
    """With cds_enable=1, FSM should pass through CDS state before INTEGRATE."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    dut.reset_us.value         = 1
    dut.cds_delay_us.value     = 2
    dut.delay_time.value       = 1
    dut.pixel_dwell_time.value = 1
    dut.cds_enable.value       = 1
    dut.read_mode.value        = 0

    await pulse_start(dut)

    reached = await wait_for_signal(dut, dut.cds_state, timeout_us=5000)
    assert reached, "CDS state never entered with cds_enable=1"
    assert dut.nRES.value == 1, "nRES should be deasserted during CDS"
    assert dut.nTX.value  == 1, "nTX should be deasserted during CDS"
    dut._log.info("CDS state confirmed")


@cocotb.test()
async def test_single_pixel_mode(dut):
    """Single-pixel mode: AX/AY should hold the selected address."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    dut.reset_us.value         = 1
    dut.delay_time.value       = 1
    dut.pixel_dwell_time.value = 1
    dut.cds_enable.value       = 0
    dut.read_mode.value        = 1   # single pixel
    dut.px_select.value        = 3
    dut.py_select.value        = 5

    await pulse_start(dut)

    reached = await wait_for_signal(dut, dut.single_pix_state, timeout_us=5000)
    assert reached, "SINGLE_PIXEL state never entered"

    await RisingEdge(dut.clk)
    assert int(dut.AX.value) == 3, f"Expected AX=3, got {int(dut.AX.value)}"
    assert int(dut.AY.value) == 5, f"Expected AY=5, got {int(dut.AY.value)}"

    reached = await wait_for_signal(dut, dut.single_done, timeout_us=5000)
    assert reached, "single_done never asserted"
    dut._log.info(f"Single pixel read at ({int(dut.AX.value)}, {int(dut.AY.value)})")
