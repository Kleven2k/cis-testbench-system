"""
CIS Testbench Control GUI
UART register interface for sensor_ctrl parameters.

Protocol:
  Write: AA <addr> <data> 55
  Read:  BB <addr> 55
  Response: CC <addr> <data> 55

Register map:
  0x00  CTRL: [7]=remote_mode [2]=cds_enable [1]=soft_reset [0]=start
  0x01  exposure_us[7:0]
  0x02  exposure_us[15:8]
  0x03  dwell_us[7:0]
  0x04  dwell_us[15:8]
  0x05  mode: [0]=read_mode
  0x06  reset_us  (0-255)
  0x07  cds_delay_us (0-255)
"""

import tkinter as tk
from tkinter import ttk, messagebox
import serial
import serial.tools.list_ports
import threading
import time

# ──────────────────────────────────────────────
# Register addresses
# ──────────────────────────────────────────────
REG_CTRL        = 0x00
REG_EXP_LO     = 0x01
REG_EXP_HI     = 0x02
REG_DWELL_LO   = 0x03
REG_DWELL_HI   = 0x04
REG_MODE        = 0x05
REG_RESET_US    = 0x06
REG_CDS_US      = 0x07

CTRL_START      = 0x01
CTRL_SOFT_RST   = 0x02
CTRL_CDS_EN     = 0x04
CTRL_REMOTE     = 0x80


class CISControl:
    def __init__(self, root):
        self.root = root
        self.root.title("CIS Sensor Control")
        self.root.resizable(False, False)

        self.port = None
        self.remote_active = False

        self._build_ui()

    # ──────────────────────────────────────────
    # UI construction
    # ──────────────────────────────────────────
    def _build_ui(self):
        pad = dict(padx=8, pady=4)

        # ── Port selection ──
        port_frame = ttk.LabelFrame(self.root, text="Serial Port")
        port_frame.grid(row=0, column=0, columnspan=2, sticky="ew", **pad)

        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(port_frame, textvariable=self.port_var, width=14, state="readonly")
        self.port_combo.grid(row=0, column=0, padx=4, pady=4)

        ttk.Button(port_frame, text="Refresh", command=self._refresh_ports).grid(row=0, column=1, padx=4)
        ttk.Button(port_frame, text="Connect", command=self._connect).grid(row=0, column=2, padx=4)

        self.status_label = ttk.Label(port_frame, text="Disconnected", foreground="red")
        self.status_label.grid(row=0, column=3, padx=8)

        self._refresh_ports()

        # ── Timing parameters ──
        timing_frame = ttk.LabelFrame(self.root, text="Timing Parameters")
        timing_frame.grid(row=1, column=0, columnspan=2, sticky="ew", **pad)

        self.exposure_var  = tk.IntVar(value=100)
        self.dwell_var     = tk.IntVar(value=100)
        self.reset_us_var  = tk.IntVar(value=10)
        self.cds_delay_var = tk.IntVar(value=2)

        params = [
            ("Exposure time (µs)",  self.exposure_var,  1, 65535, 1),
            ("Pixel dwell (µs)",    self.dwell_var,     1, 65535, 1),
            ("Reset hold (µs)",     self.reset_us_var,  1,   255, 1),
            ("CDS delay (µs)",      self.cds_delay_var, 1,   255, 1),
        ]

        for i, (label, var, lo, hi, step) in enumerate(params):
            ttk.Label(timing_frame, text=label, width=22, anchor="w").grid(row=i, column=0, padx=4, pady=3)
            scale = ttk.Scale(timing_frame, from_=lo, to=hi, variable=var, orient="horizontal", length=260)
            scale.grid(row=i, column=1, padx=4)
            val_label = ttk.Label(timing_frame, textvariable=var, width=6)
            val_label.grid(row=i, column=2, padx=2)
            spin = ttk.Spinbox(timing_frame, from_=lo, to=hi, textvariable=var, width=7, increment=step)
            spin.grid(row=i, column=3, padx=4)

        # ── Mode flags ──
        flags_frame = ttk.LabelFrame(self.root, text="Mode")
        flags_frame.grid(row=2, column=0, columnspan=2, sticky="ew", **pad)

        self.cds_en_var   = tk.BooleanVar(value=False)
        self.read_mode_var = tk.BooleanVar(value=False)

        ttk.Checkbutton(flags_frame, text="CDS enable",      variable=self.cds_en_var).grid(row=0, column=0, padx=10, pady=4)
        ttk.Checkbutton(flags_frame, text="Single-pixel mode", variable=self.read_mode_var).grid(row=0, column=1, padx=10)

        # ── Actions ──
        action_frame = ttk.LabelFrame(self.root, text="Control")
        action_frame.grid(row=3, column=0, columnspan=2, sticky="ew", **pad)

        self.remote_btn = ttk.Button(action_frame, text="Enable Remote", command=self._toggle_remote)
        self.remote_btn.grid(row=0, column=0, padx=8, pady=6)

        ttk.Button(action_frame, text="Apply Settings", command=self._apply_settings).grid(row=0, column=1, padx=8)
        ttk.Button(action_frame, text="Start Scan",     command=self._start_scan).grid(row=0, column=2, padx=8)
        ttk.Button(action_frame, text="Soft Reset",     command=self._soft_reset).grid(row=0, column=3, padx=8)

        # ── Log ──
        log_frame = ttk.LabelFrame(self.root, text="Log")
        log_frame.grid(row=4, column=0, columnspan=2, sticky="ew", **pad)

        self.log = tk.Text(log_frame, height=6, width=62, state="disabled", font=("Courier", 9))
        self.log.grid(row=0, column=0, padx=4, pady=4)
        sb = ttk.Scrollbar(log_frame, command=self.log.yview)
        sb.grid(row=0, column=1, sticky="ns")
        self.log.configure(yscrollcommand=sb.set)

    # ──────────────────────────────────────────
    # Serial helpers
    # ──────────────────────────────────────────
    def _refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if ports:
            self.port_combo.set(ports[0])

    def _connect(self):
        if self.port and self.port.is_open:
            self.port.close()
            self.port = None
            self.status_label.config(text="Disconnected", foreground="red")
            self.remote_active = False
            self.remote_btn.config(text="Enable Remote")
            self._log("Disconnected.")
            return

        selected = self.port_var.get()
        if not selected:
            messagebox.showerror("Error", "No port selected.")
            return
        try:
            self.port = serial.Serial(selected, 115200, timeout=0.5)
            self.status_label.config(text=f"Connected: {selected}", foreground="green")
            self._log(f"Connected to {selected} @ 115200 baud.")
        except Exception as e:
            messagebox.showerror("Connection failed", str(e))

    def _write_reg(self, addr, data):
        if not self.port or not self.port.is_open:
            self._log("Not connected.")
            return
        pkt = bytes([0xAA, addr, data, 0x55])
        self.port.write(pkt)
        self._log(f"  WR  addr=0x{addr:02X}  data=0x{data:02X}")

    def _read_reg(self, addr):
        if not self.port or not self.port.is_open:
            return None
        pkt = bytes([0xBB, addr, 0x55])
        self.port.write(pkt)
        resp = self.port.read(4)
        if len(resp) == 4 and resp[0] == 0xCC and resp[1] == addr and resp[3] == 0x55:
            self._log(f"  RD  addr=0x{addr:02X}  data=0x{resp[2]:02X}")
            return resp[2]
        self._log(f"  RD  addr=0x{addr:02X}  bad response: {resp.hex()}")
        return None

    # ──────────────────────────────────────────
    # Actions
    # ──────────────────────────────────────────
    def _toggle_remote(self):
        if not self.port or not self.port.is_open:
            messagebox.showwarning("Not connected", "Connect to the FPGA first.")
            return

        if not self.remote_active:
            self._write_reg(REG_CTRL, CTRL_REMOTE)
            self.remote_active = True
            self.remote_btn.config(text="Disable Remote")
            self._log("Remote mode ENABLED.")
        else:
            self._write_reg(REG_CTRL, 0x00)
            self.remote_active = False
            self.remote_btn.config(text="Enable Remote")
            self._log("Remote mode DISABLED — hardware controls active.")

    def _apply_settings(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return

        exp   = self.exposure_var.get()
        dwell = self.dwell_var.get()
        rst   = self.reset_us_var.get()
        cds   = self.cds_delay_var.get()

        self._log(f"Applying: exp={exp}µs  dwell={dwell}µs  reset={rst}µs  cds={cds}µs")

        self._write_reg(REG_EXP_LO,   exp   & 0xFF)
        self._write_reg(REG_EXP_HI,   (exp  >> 8) & 0xFF)
        self._write_reg(REG_DWELL_LO, dwell & 0xFF)
        self._write_reg(REG_DWELL_HI, (dwell >> 8) & 0xFF)
        self._write_reg(REG_RESET_US, rst  & 0xFF)
        self._write_reg(REG_CDS_US,   cds  & 0xFF)

        # Update CTRL with mode flags (keep remote bit set)
        ctrl = CTRL_REMOTE
        if self.cds_en_var.get():
            ctrl |= CTRL_CDS_EN
        mode = 0x01 if self.read_mode_var.get() else 0x00
        self._write_reg(REG_CTRL, ctrl)
        self._write_reg(REG_MODE, mode)

    def _start_scan(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return

        self._apply_settings()

        # Pulse start bit (write 1, then 0)
        ctrl = CTRL_REMOTE | CTRL_START
        if self.cds_en_var.get():
            ctrl |= CTRL_CDS_EN
        self._log("Sending START pulse...")
        self._write_reg(REG_CTRL, ctrl)
        time.sleep(0.05)
        ctrl &= ~CTRL_START
        self._write_reg(REG_CTRL, ctrl)

    def _soft_reset(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return
        self._log("Soft reset...")
        ctrl = CTRL_REMOTE | CTRL_SOFT_RST
        self._write_reg(REG_CTRL, ctrl)
        time.sleep(0.05)
        self._write_reg(REG_CTRL, CTRL_REMOTE)

    # ──────────────────────────────────────────
    # Logging
    # ──────────────────────────────────────────
    def _log(self, msg):
        self.log.config(state="normal")
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.log.config(state="disabled")


def main():
    root = tk.Tk()
    app = CISControl(root)
    root.mainloop()


if __name__ == "__main__":
    main()
