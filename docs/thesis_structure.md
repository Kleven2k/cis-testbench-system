# Thesis Structure

**Title**: Testbench System for CMOS Image Sensor Characterization
**Author**: Fredrik G. Kleven
**Supervisor**: Philipp Häfliger
**Institution**: University of Oslo, Department of Physics
**Program**: Electronics, Informatics and Technology

---

## Chapter 1 — Introduction

**Goal**: Set the scene and state the problem clearly.

- The Nanoelectronics group's long tradition of CIS chip development
- The recurring problem: every student rebuilds the test infrastructure from scratch
- Why this is inefficient and what a standardized testbench would solve
- The decision to use the Digilent Nexys Video FPGA board as the platform
- Scope of this thesis: firmware implementation + characterization of an 8x8 CIS prototype
- Thesis outline (one paragraph describing each chapter)

**Tip**: Write this chapter last. It is much easier to introduce something you have already written about.

---

## Chapter 2 — Background

**Goal**: Give the reader enough theory to understand your design decisions.

### Suggested sections:
- **CMOS image sensors**: photodiode operation, pixel architectures (3T, 4T), readout chain
- **Noise in image sensors**: thermal noise, kTC noise, fixed-pattern noise — why they matter for characterization
- **Correlated Double Sampling (CDS)**: what it removes and how (reset level subtraction)
- **Analog-to-digital conversion**: basics of successive approximation ADC, Xilinx XADC specifics (12-bit, 1 MSPS, differential inputs)
- **FPGA-based test platforms**: why FPGAs are well suited for this (precise timing, reconfigurability)
- **Prior work in the group**: brief mention of previous student setups this system replaces

**Tip**: Don't over-explain standard textbook material. Cite a reference and move on. Focus depth on CDS and the XADC since these are central to your design.

---

## Chapter 3 — Hardware

**Goal**: Describe the physical system — what is connected to what and why.

### Suggested sections:
- **Platform selection**: why Nexys Video over a custom PCB (time-to-market, built-in HDMI, proven XADC, reusability for future students)
- **The CIS chip under test**: 8x8 pixel array architecture, control signal interface (nRES, nTX, AX, AY), analog output characteristics
- **Analog front-end**: how the sensor output is connected to XADC VAUX0, differential signal path
- **PMOD connections**: which pins carry which signals (AY[2:0], nTX, AX[2:0], nRES on PMOD JA)
- **HDMI output**: physical connector, TMDS differential pairs
- **UART interface**: USB-UART bridge on the board, baud rate, PC connection
- **Board-level block diagram**: a figure showing all physical connections

**Key figure**: A hardware connection diagram (sensor chip ↔ PMOD ↔ FPGA ↔ HDMI monitor + PC).

---

## Chapter 4 — System Architecture

**Goal**: Describe the overall firmware design before diving into implementation details.

### Suggested sections:
- **Top-level block diagram**: all major modules and their connections (`cis_system_top.sv`)
- **Clock domains**:
  - 100 MHz — system, UART, XADC, OLED
  - 74.25 MHz — pixel clock, sensor FSM
  - 371.25 MHz — TMDS serializer
- **Clock domain crossing (CDC)**: how data moves safely between domains (`cdc_adc_sync`)
- **UART register protocol**: packet framing (0xAA/0xBB/0x55), the 8-register map, read/write transactions
- **Dual control mode**: local (buttons + switches) vs. remote (UART from PC), how `remote_mode` arbitrates

**Key figure**: Top-level block diagram with clock domain boundaries marked.

---

## Chapter 5 — FPGA Design & Implementation

**Goal**: The deep dive — how each subsystem is built.

### Suggested sections:
- **Sensor control FSM**: the 6 states (IDLE → RESET → CDS → INTEGRATE → READOUT / SINGLE_PIXEL → back), timing diagrams for each transition, configurable parameters (exposure_us, dwell_us, reset_us, cds_delay_us)
- **XADC integration**: channel multiplexing (VAUX0 = sensor, VAUX1 = temperature), 12-bit result handling, sampling timing relative to pixel dwell
- **Pixel frame buffer**: 64-element 12-bit array, how it is written during readout and read during display
- **HDMI display chain**: 720p sync generator → `simple_pixel` renderer (8x8 grid layout) → TMDS encoder → OSERDES serializer
- **OLED display**: SPI driver, what is shown (exposure time, status)
- **Python host software**: GUI layout, how it maps to the register file, serial port handling

**Key figures**:
- FSM state diagram with transitions and timing parameters labelled
- Timing diagram showing one full readout cycle (nRES, nTX, AX, AY, ADC sample point)

---

## Chapter 6 — Verification

**Goal**: Show that the design was tested before hardware experiments.

### Suggested sections:
- **Simulation strategy**: system-level testbench (`cis_system_top_tb.sv`), unit testbench for sensor FSM (`sensor_ctrl_tb.vhd`), module stubs for heavyweight IPs
- **Key simulation results**: waveforms showing FSM state transitions, correct timing of control signals, ADC readback
- **Hardware bring-up**: how the board was first tested, what debugging was needed

**Tip**: Even if simulation was limited, include what you did. A chapter showing you thought about verification is better than skipping it.

---

## Chapter 7 — Experimental Results

**Goal**: Show what the system can actually measure.

### Suggested sections:
- **Timing verification**: oscilloscope captures of nRES, nTX, AX/AY signals — do they match the configured timing?
- **Dark frame**: ADC output with sensor covered — shows noise floor and fixed-pattern noise
- **Flat-field response**: uniform illumination — shows pixel-to-pixel gain variation
- **CDS effectiveness**: compare noise with CDS disabled vs. enabled — quantify the improvement
- **Image captures**: example captures of a simple scene or light source

**Tip**: Even if results are imperfect or unexpected, discuss them honestly. Explaining *why* something didn't work as expected is good engineering writing.

---

## Chapter 8 — Discussion

**Goal**: Step back and evaluate the work critically.

- Does the system meet the original goals from the project plan?
- What works well?
- What are the limitations (8x8 array, 12-bit XADC resolution, no lens/optics)
- How reusable is it for future students — what would they need to change to plug in a new sensor?
- Comparison to alternative approaches (commercial sensor evaluation boards, lab instruments)

---

## Chapter 9 — Conclusion & Future Work

**Goal**: Close the thesis cleanly.

- Summary of what was designed and implemented
- Key results in 2-3 sentences
- **Future work**:
  - Custom adapter PCB for different sensor packages
  - External high-resolution ADC (the XADC's 12-bit / 1 MSPS is limiting)
  - Automated test scripts (dark frame subtraction, FPN correction in software)
  - Optics mount and controlled light source for proper characterization
  - Support for larger pixel arrays

---

## General Writing Tips

- **Write the abstract last** — it summarizes everything else
- **Every figure needs a caption** that is self-contained (readable without the surrounding text)
- **Every figure must be referenced** in the body text before it appears ("as shown in Figure X")
- **Use past tense** for what you did ("the FSM was implemented as..."), present tense for facts ("the XADC produces a 12-bit result")
- **Avoid "I"** — use "this work", "the system", or passive voice
- **Be specific** — "the exposure time was set to 500 µs" is better than "the exposure time was configured"
- **Cite early** — when you mention CDS, TMDS, or any standard technique, cite a reference immediately

---

## Workflow: Writing & Syncing

### Pull changes from Overleaf to local repo:
```bash
git fetch overleaf && git merge -s subtree overleaf/master -m "Pull from Overleaf"
```

### Push local changes to Overleaf:
```bash
git checkout -b overleaf-sync overleaf/master
git merge -s subtree master --allow-unrelated-histories -X theirs -m "Push to Overleaf"
git push overleaf overleaf-sync:master
git checkout master
git branch -D overleaf-sync
```

### Push everything to GitHub:
```bash
git push origin master
```
