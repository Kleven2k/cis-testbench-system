"""
cocotb tests for cdc_adc_sync.

Verifies that 12-bit XADC results are safely transferred from the
100 MHz source domain to the 74.25 MHz destination domain using the
toggle-based handshake.

Simulation clocks:
  clk_src = 100 MHz  (10 ns period)
  clk_dst = 74.25 MHz (13.47 ns period)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

CLK_SRC_PERIOD_NS = 10.0    # 100 MHz
CLK_DST_PERIOD_NS = 13.47   # ~74.25 MHz

# CDC synchroniser latency: up to 3 clk_dst cycles + 1 output register stage
CDC_LATENCY_CYCLES = 6


async def init_dut(dut):
    dut.data_sensor_in.value = 0
    dut.data_temp_in.value   = 0
    dut.data_valid.value     = 0
    await Timer(50, unit="ns")


async def send_sample(dut, sensor_val, temp_val):
    """Assert data_valid for one clk_src cycle with given values."""
    await RisingEdge(dut.clk_src)
    dut.data_sensor_in.value = sensor_val
    dut.data_temp_in.value   = temp_val
    dut.data_valid.value     = 1
    await RisingEdge(dut.clk_src)
    dut.data_valid.value     = 0


async def wait_for_output(dut, expected_sensor, expected_temp, timeout=30):
    """Poll data_sensor_out / data_temp_out on clk_dst until values match."""
    for _ in range(timeout):
        await RisingEdge(dut.clk_dst)
        if (int(dut.data_sensor_out.value) == expected_sensor and
                int(dut.data_temp_out.value) == expected_temp):
            return
    raise AssertionError(
        f"Timeout: expected sensor=0x{expected_sensor:03X} temp=0x{expected_temp:03X}, "
        f"got sensor=0x{int(dut.data_sensor_out.value):03X} "
        f"temp=0x{int(dut.data_temp_out.value):03X}"
    )


# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_single_transfer(dut):
    """A single data_valid pulse transfers both sensor and temp values."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    await send_sample(dut, sensor_val=0xABC, temp_val=0x123)
    await wait_for_output(dut, 0xABC, 0x123)
    dut._log.info("Single transfer: sensor=0xABC temp=0x123 — OK")


@cocotb.test()
async def test_zero_values(dut):
    """Transfer of all-zero values propagates correctly."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    await send_sample(dut, 0x000, 0x000)
    await wait_for_output(dut, 0x000, 0x000)
    dut._log.info("Zero transfer — OK")


@cocotb.test()
async def test_max_values(dut):
    """Transfer of all-ones (0xFFF) values propagates correctly."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    await send_sample(dut, 0xFFF, 0xFFF)
    await wait_for_output(dut, 0xFFF, 0xFFF)
    dut._log.info("Max values transfer — OK")


@cocotb.test()
async def test_sequential_transfers(dut):
    """Several sequential samples each arrive with the correct values."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    samples = [
        (0x100, 0x200),
        (0x300, 0x400),
        (0xAAA, 0x555),
        (0x7FF, 0x800),
    ]

    for sensor_val, temp_val in samples:
        await send_sample(dut, sensor_val, temp_val)
        # Wait enough clk_src cycles between sends so the CDC handshake completes
        await ClockCycles(dut.clk_src, 20)
        await wait_for_output(dut, sensor_val, temp_val)
        dut._log.info(f"Transfer sensor=0x{sensor_val:03X} temp=0x{temp_val:03X} — OK")


@cocotb.test()
async def test_data_stable_without_valid(dut):
    """Output holds its last value when no new data_valid pulse is sent."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    await send_sample(dut, 0x5A5, 0xA5A)
    await wait_for_output(dut, 0x5A5, 0xA5A)

    # Wait many cycles with no new valid — output must not change
    await ClockCycles(dut.clk_dst, 20)

    assert int(dut.data_sensor_out.value) == 0x5A5, \
        f"sensor output changed without data_valid: 0x{int(dut.data_sensor_out.value):03X}"
    assert int(dut.data_temp_out.value) == 0xA5A, \
        f"temp output changed without data_valid: 0x{int(dut.data_temp_out.value):03X}"
    dut._log.info("Output held stable without data_valid — OK")


@cocotb.test()
async def test_latency_within_bound(dut):
    """Transfer completes within CDC_LATENCY_CYCLES clk_dst cycles."""
    cocotb.start_soon(Clock(dut.clk_src, CLK_SRC_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_dst, CLK_DST_PERIOD_NS, unit="ns").start())
    await init_dut(dut)

    await send_sample(dut, 0xDEA, 0xDBE)

    for i in range(CDC_LATENCY_CYCLES):
        await RisingEdge(dut.clk_dst)
        if (int(dut.data_sensor_out.value) == 0xDEA and
                int(dut.data_temp_out.value) == 0xDBE):
            dut._log.info(f"Transfer completed in {i+1} clk_dst cycles — OK")
            return

    raise AssertionError(
        f"Transfer did not complete within {CDC_LATENCY_CYCLES} clk_dst cycles"
    )
