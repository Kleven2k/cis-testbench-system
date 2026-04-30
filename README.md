# CIS Testbench System

FPGA-based testbench for CMOS image sensor (CIS) characterisation, developed at the
Nanoelectronics group, University of Oslo.

**Platform:** Digilent Nexys Video (Xilinx Artix-7 xc7a200tsbg484-1)  
**Toolchain:** Vivado 2024.2 / Python 3

---

## System Overview

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  Nexys Video FPGA                   │
                    │                                                     │
 100 MHz osc ──────►│ clk_720p ──► 74.25 MHz (pixel clock)               │
                    │           └► 371.25 MHz (TMDS serialiser)          │
                    │                                                     │
 Buttons/Switches ─►│ debounce ──► control_regs ──► sensor_ctrl FSM ─────┼──► PMOD JA
                    │                  ▲                  │               │    (nRES, nTX,
 PC (UART) ────────►│ uart_rx          │                  │               │     AX, AY)
                    │ uart_tx ◄────────┤                  │               │
                    │                                     ▼               │
 Sensor analog ────►│ XADC (VAUX0) ──► cdc_adc_sync ──► pixel_mem        │
                    │                                     │               │
                    │                             simple_pixel renderer   │
                    │                                     │               │
                    │                             dvi_generator ──────────┼──► HDMI
                    │                                                     │
                    │ OLED_master ───────────────────────────────────────┼──► OLED
                    └─────────────────────────────────────────────────────┘
```

---

## Hardware Setup

### Requirements
- Digilent Nexys Video board
- CIS sensor chip with standard 3T/4T pixel interface
- HDMI monitor (720p)
- USB cable (UART + power)

### PMOD JA — Sensor Control Signals

| PMOD Pin | Signal   | Direction |
|----------|----------|-----------|
| JA1      | `AY[0]`  | Output    |
| JA2      | `AY[1]`  | Output    |
| JA3      | `AY[2]`  | Output    |
| JA4      | `nTX`    | Output    |
| JA7      | `AX[0]`  | Output    |
| JA8      | `AX[1]`  | Output    |
| JA9      | `AX[2]`  | Output    |
| JA10     | `nRES`   | Output    |

### XADC Analog Input

| Channel | Signal              |
|---------|---------------------|
| VAUX0   | Sensor pixel output |
| VAUX1   | Temperature monitor |

Connect the sensor analog output to the XADC VAUX0 differential input pair.
The positive input carries the sensor signal; the negative input connects to analog ground.

### Switch Assignments (Local Mode)

| Switch  | Function                              |
|---------|---------------------------------------|
| `SW[0]` | CDS enable                            |
| `SW[1]` | Photosense mode (skip alternate pixels)|
| `SW[2]` | Invert polarity (higher ADC = brighter)|

### Button Assignments

| Button | Function                  |
|--------|---------------------------|
| BTNC   | Start scan                |
| BTNU   | Increase exposure time    |
| BTNL   | Decrease exposure time    |
| BTNR   | Increase dwell time       |
| BTND   | Decrease dwell time       |
| CPU_RESETN | System reset          |

---

## Building the Bitstream

1. Open `cis_testbench_system.xpr` in Vivado 2024.2
2. To change the maximum array size, edit `GRID_COLS` and `GRID_ROWS` parameters
   in `hdl/rtl/top/cis_system_top.sv` (default 8×8, maximum 16×16)
3. Run **Generate Bitstream** (Implementation → Generate Bitstream)
4. Program the board via **Open Hardware Manager → Program Device**

> The active scan area is set at runtime via the Python GUI — a bitstream rebuild
> is only needed when changing the **maximum** supported array size.

---

## Python GUI

### Installation

```bash
pip install pyserial
```

### Running

```bash
cd scripts
python cis_control.py
```

### Usage

1. Set **Columns** and **Rows** to match your sensor array in the Sensor Config panel
2. Select the correct COM port and click **Connect**
   - The GUI automatically writes the grid size to the FPGA on connect
3. Click **Enable Remote** to switch to PC control
4. Set timing parameters (exposure, dwell, reset hold, CDS delay)
5. Click **Apply Settings** then **Start Scan**
6. Click **Read Frame** to read back pixel values over UART
7. Enable **Live View** for continuous capture

### Tips
- Use **Set Dark Frame** to capture a dark reference — the canvas will show
  deviation from dark rather than raw ADC values
- **Invert polarity** if bright pixels appear dark (depends on sensor type)
- Increase **HDMI gain** if the image looks flat (low contrast scene)

---

## Register Map

| Address | Name        | Description                                              |
|---------|-------------|----------------------------------------------------------|
| `0x00`  | CTRL        | `[7]` remote_mode, `[2]` cds_enable, `[1]` soft_reset, `[0]` start |
| `0x01`  | EXP_LO      | Exposure time low byte (µs)                              |
| `0x02`  | EXP_HI      | Exposure time high byte (µs)                             |
| `0x03`  | DWELL_LO    | Pixel dwell time low byte (µs)                           |
| `0x04`  | DWELL_HI    | Pixel dwell time high byte (µs)                          |
| `0x05`  | MODE        | `[4]` invert_pol, `[3:2]` disp_gain, `[1]` photosense, `[0]` read_mode |
| `0x06`  | RESET_US    | Reset hold duration (µs)                                 |
| `0x07`  | CDS_DELAY   | CDS window duration (µs)                                 |
| `0x08`  | ACTIVE_COLS | Runtime grid columns (1–64, written by GUI on connect)   |
| `0x09`  | ACTIVE_ROWS | Runtime grid rows (1–64, written by GUI on connect)      |
| `0x0A+` | Pixel data  | `0x0A + i*2` = pixel[i] hi nibble, `+1` = lo byte       |

### UART Protocol

```
Write:    0xAA <addr> <data> 0x55
Read:     0xBB <addr> 0x55
Response: 0xCC <addr> <data> 0x55
Baud:     115200, 8N1
```

---

## Running Simulations

### cocotb unit tests (uart, uart_reg_if, control_regs, cdc_adc_sync)

```bash
cd sim/cocotb/<module>
python runner_<module>.py          # run all tests
python runner_<module>.py <test>   # run one test
```

### sensor_ctrl FSM (cocotb + ModelSim)

```bash
cd sim/cocotb/sensor_ctrl
make
```

Requires ModelSim to be on PATH.

---

## Adapting for a New Sensor

1. **PMOD wiring** — connect the new sensor's control signals to PMOD JA
   and update `constraints/nexys_video.xdc` if pin assignments change
2. **Grid size** — set `GRID_COLS`/`GRID_ROWS` in `cis_system_top.sv`
   to the maximum array size and rebuild the bitstream
3. **FSM** — modify `hdl/rtl/control/sensor_ctrl.vhd` if the sensor
   uses a different readout protocol (rolling shutter, column-parallel, etc.)
4. **Polarity** — set `invert_pol` from the GUI to match the sensor's
   output convention (no rebuild needed)

---

## Repository Structure

```
cis_testbench_system/
├── hdl/
│   ├── rtl/                    RTL source (SystemVerilog + VHDL)
│   │   ├── top/                cis_system_top.sv
│   │   ├── control/            sensor_ctrl.vhd, control_regs.sv
│   │   ├── uart/               uart_tx.sv, uart_rx.sv, uart_reg_if.sv
│   │   ├── display/            HDMI chain, OLED driver
│   │   ├── clock/              clk_720p.sv (MMCM)
│   │   ├── interface/          cdc_adc_sync.sv
│   │   └── common/             debounce.sv
│   └── tb/                     Legacy ModelSim testbenches + stubs
├── sim/cocotb/                 cocotb unit tests
├── constraints/                Vivado XDC files
├── scripts/                    Python GUI (cis_control.py)
├── data/frames/                Saved frame captures
├── figures/scope/              Oscilloscope captures
├── docs/                       Project documentation
└── cis_testbench_system.xpr    Vivado 2024.2 project file
```

---

## Author

Fredrik G. Kleven — University of Oslo, Department of Physics  
Supervisor: Philipp Häfliger
