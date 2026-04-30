"""
cocotb tests for uart_reg_if.

Tests the full UART register interface protocol:
  Write: AA <addr> <data> 55
  Read:  BB <addr> 55  ->  CC <addr> <data> 55

Key regression: the TX race condition fixed by tx_busy_d / tx_done.
Before the fix, consecutive TX states fired in the 1-cycle gap before
uart_tx asserted tx_busy, producing only 2 bytes (CC + data) instead
of 4 (CC + addr + data + 55).

Simulation parameters (set in wrapper):
  CLK_FREQ = 10 MHz, BAUD = 1 Mbaud -> 10 cycles/bit
  CLK period = 100 ns
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 100   # 10 MHz
CYCLES_PER_BIT = 10


async def reset_dut(dut):
    dut.rst.value            = 1
    dut.host_tx_start.value  = 0
    dut.host_tx_data.value   = 0
    dut.mem_write_en.value   = 0
    dut.mem_write_addr.value = 0
    dut.mem_write_data.value = 0
    dut.read_addr_override.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def send_byte(dut, byte):
    """Send one byte from host TX and wait until transmission finishes."""
    await RisingEdge(dut.clk)
    dut.host_tx_data.value  = byte
    dut.host_tx_start.value = 1
    await RisingEdge(dut.clk)
    dut.host_tx_start.value = 0
    # Wait for tx_busy to assert (uart_tx needs 1 cycle to raise it)
    for _ in range(10):
        if dut.host_tx_busy.value == 1:
            break
        await RisingEdge(dut.clk)
    # Now wait for tx_busy to deassert (transmission complete)
    while dut.host_tx_busy.value == 1:
        await RisingEdge(dut.clk)


async def send_frame(dut, *bytes_):
    """Send a multi-byte frame with one bit-period gap between bytes."""
    for b in bytes_:
        await send_byte(dut, b)
        await ClockCycles(dut.clk, CYCLES_PER_BIT)


async def recv_byte(dut, timeout_cycles=500):
    """Wait for host_rx_valid and return the received byte value."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.host_rx_valid.value == 1:
            return int(dut.host_rx_data.value)
    raise AssertionError("Timed out waiting for response byte")


async def recv_frame(dut, n, timeout_cycles=500):
    """Receive n bytes and return them as a list (loop, not comprehension)."""
    result = []
    for _ in range(n):
        result.append(await recv_byte(dut, timeout_cycles))
    return result


async def wait_for_write_en(dut, timeout_cycles=2000):
    """
    Wait for write_en to pulse high and capture addr/data at that moment.
    Returns (addr, data) or raises AssertionError on timeout.
    write_en is a single-cycle pulse so we must catch it on the rising edge.
    """
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.write_en.value == 1:
            return int(dut.write_addr.value), int(dut.write_data.value)
    raise AssertionError("Timed out waiting for write_en pulse")


async def mem_load(dut, addr, value):
    """Pre-load a value into the read memory at the given address."""
    await RisingEdge(dut.clk)
    dut.mem_write_addr.value = addr
    dut.mem_write_data.value = value
    dut.mem_write_en.value   = 1
    await RisingEdge(dut.clk)
    dut.mem_write_en.value   = 0


# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_write_frame(dut):
    """Write frame AA <addr> <data> 55 should assert write_en with correct addr/data."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await send_frame(dut, 0xAA, 0x05, 0xA3, 0x55)

    addr, data = await wait_for_write_en(dut)
    assert addr == 0x05, f"write_addr: expected 0x05 got 0x{addr:02X}"
    assert data == 0xA3, f"write_data: expected 0xA3 got 0x{data:02X}"
    dut._log.info("Write frame: write_en asserted with correct addr/data")


@cocotb.test()
async def test_write_bad_footer(dut):
    """Write frame with wrong footer should NOT assert write_en."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await send_frame(dut, 0xAA, 0x05, 0xA3, 0xAA)  # bad footer: 0xAA instead of 0x55

    # write_en must not pulse within 200 cycles after the last byte
    fired = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if dut.write_en.value == 1:
            fired = True
            break
    assert not fired, "write_en should NOT be asserted with bad footer"
    dut._log.info("Bad footer correctly rejected")


@cocotb.test()
async def test_read_full_response(dut):
    """
    Read frame BB <addr> 55 must produce exactly 4 response bytes: CC <addr> <data> 55.

    REGRESSION: before the tx_busy_d fix, consecutive TX states fired in the
    1-cycle gap before uart_tx asserted tx_busy.  The response was only 2 bytes
    (CC + data), missing the addr echo and footer.  This test catches that.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await mem_load(dut, 0x03, 0x7E)   # pre-load addr 0x03 → value 0x7E

    await send_frame(dut, 0xBB, 0x03, 0x55)

    resp = await recv_frame(dut, 4, timeout_cycles=1000)

    assert resp[0] == 0xCC, f"byte 0: expected 0xCC (header) got 0x{resp[0]:02X}"
    assert resp[1] == 0x03, f"byte 1: expected 0x03 (addr echo) got 0x{resp[1]:02X}"
    assert resp[2] == 0x7E, f"byte 2: expected 0x7E (data) got 0x{resp[2]:02X}"
    assert resp[3] == 0x55, f"byte 3: expected 0x55 (footer) got 0x{resp[3]:02X}"
    dut._log.info(f"Read response: {[f'0x{b:02X}' for b in resp]}")


@cocotb.test()
async def test_read_response_byte_count(dut):
    """
    Verify exactly 4 bytes arrive and no 5th byte appears within a timeout.

    If the race condition is present, only 2 bytes arrive; this test would
    either time out on byte 3 or catch a spurious extra byte.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await mem_load(dut, 0x10, 0xAB)

    await send_frame(dut, 0xBB, 0x10, 0x55)

    resp = await recv_frame(dut, 4, timeout_cycles=1000)

    # Check no 5th byte arrives in the next 300 cycles
    spurious = False
    for _ in range(300):
        await RisingEdge(dut.clk)
        if dut.host_rx_valid.value == 1:
            spurious = True
            break

    assert not spurious, "Spurious 5th byte received — TX state machine fired extra bytes"
    dut._log.info("Exactly 4 bytes received, no spurious extra bytes")


@cocotb.test()
async def test_read_multiple_addresses(dut):
    """Read three different addresses in sequence and verify each response."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    test_cases = [(0x00, 0x80), (0x01, 0x64), (0x02, 0x00)]

    for addr, expected in test_cases:
        await mem_load(dut, addr, expected)

    for addr, expected in test_cases:
        await send_frame(dut, 0xBB, addr, 0x55)
        resp = await recv_frame(dut, 4, timeout_cycles=1000)

        assert resp[0] == 0xCC,     f"addr 0x{addr:02X}: bad header 0x{resp[0]:02X}"
        assert resp[1] == addr,     f"addr 0x{addr:02X}: echo mismatch 0x{resp[1]:02X}"
        assert resp[2] == expected, f"addr 0x{addr:02X}: data 0x{resp[2]:02X} != 0x{expected:02X}"
        assert resp[3] == 0x55,     f"addr 0x{addr:02X}: bad footer 0x{resp[3]:02X}"

        await ClockCycles(dut.clk, CYCLES_PER_BIT * 2)

    dut._log.info("All three addresses read correctly")


@cocotb.test()
async def test_idle_after_write(dut):
    """After a completed write, the DUT should return to IDLE and accept another frame."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    # First write
    await send_frame(dut, 0xAA, 0x01, 0x11, 0x55)
    addr, data = await wait_for_write_en(dut)
    assert addr == 0x01, f"first write addr: expected 0x01 got 0x{addr:02X}"
    assert data == 0x11, f"first write data: expected 0x11 got 0x{data:02X}"

    await ClockCycles(dut.clk, 20)

    # Second write — DUT must have returned to IDLE
    await send_frame(dut, 0xAA, 0x02, 0x22, 0x55)
    addr, data = await wait_for_write_en(dut)
    assert addr == 0x02, f"second write addr: expected 0x02 got 0x{addr:02X}"
    assert data == 0x22, f"second write data: expected 0x22 got 0x{data:02X}"
    dut._log.info("DUT correctly returned to IDLE and accepted second write")


@cocotb.test()
async def test_read_bad_footer(dut):
    """Read frame with wrong footer (not 0x55) should produce no response."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    await send_frame(dut, 0xBB, 0x03, 0xAA)  # bad footer

    # No response should arrive
    got_response = False
    for _ in range(500):
        await RisingEdge(dut.clk)
        if dut.host_rx_valid.value == 1:
            got_response = True
            break

    assert not got_response, "Should not produce a response for bad-footer read frame"
    dut._log.info("Bad-footer read frame correctly ignored")
