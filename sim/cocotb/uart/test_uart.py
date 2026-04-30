"""
cocotb loopback tests for uart_tx + uart_rx.

Simulation parameters (set in wrapper):
  CLK_FREQ = 10 MHz, BAUD = 1 Mbaud -> 10 cycles per bit
  CLK period = 100 ns
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 100   # 10 MHz
CYCLES_PER_BIT = 10   # CLK_FREQ / BAUD


async def reset_dut(dut):
    dut.rst.value      = 1
    dut.tx_start.value = 0
    dut.data_in.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def send_byte(dut, byte):
    """Transmit one byte and wait for tx_busy to clear."""
    await RisingEdge(dut.clk)
    dut.data_in.value  = byte
    dut.tx_start.value = 1
    await RisingEdge(dut.clk)
    dut.tx_start.value = 0

    # Wait for transmission to finish
    while dut.tx_busy.value == 1:
        await RisingEdge(dut.clk)


async def recv_byte(dut, timeout_cycles=500):
    """Wait for data_valid and return the received byte."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.data_valid.value == 1:
            return int(dut.data_out.value)
    raise cocotb.result.TestFailure("Timed out waiting for data_valid")


# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_single_byte(dut):
    """Transmit 0x55 (alternating bits) and verify it is received correctly."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    await send_byte(dut, 0x55)
    received = await recv_byte(dut)

    assert received == 0x55, f"Expected 0x55, got 0x{received:02X}"
    dut._log.info(f"Received: 0x{received:02X}")


@cocotb.test()
async def test_all_zeros(dut):
    """Transmit 0x00 — all data bits low."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    await send_byte(dut, 0x00)
    received = await recv_byte(dut)
    assert received == 0x00, f"Expected 0x00, got 0x{received:02X}"


@cocotb.test()
async def test_all_ones(dut):
    """Transmit 0xFF — all data bits high."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    await send_byte(dut, 0xFF)
    received = await recv_byte(dut)
    assert received == 0xFF, f"Expected 0xFF, got 0x{received:02X}"


@cocotb.test()
async def test_sequential_bytes(dut):
    """Transmit bytes 0x00 through 0x0F and verify each is received in order."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    for byte in range(0x10):
        await send_byte(dut, byte)
        received = await recv_byte(dut)
        assert received == byte, f"Expected 0x{byte:02X}, got 0x{received:02X}"
        await ClockCycles(dut.clk, 5)  # small gap between bytes

    dut._log.info("All 16 bytes received correctly")


@cocotb.test()
async def test_idle_high(dut):
    """TX line should be high when idle."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    await ClockCycles(dut.clk, 20)
    assert dut.tx_busy.value == 0, "tx_busy should be low when idle"
