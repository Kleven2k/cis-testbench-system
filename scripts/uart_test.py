import serial
import time

PORT = "COM5"
BAUD = 115200

REMOTE = 0x80
START  = 0x01

ser = serial.Serial(PORT, BAUD, timeout=1)


# -----------------------------
# Low-Level UART Helpers
# -----------------------------

def write_reg(addr, data):
    packet = bytes([0xAA, addr & 0xFF, data & 0xFF, 0x55])
    ser.write(packet)
    time.sleep(0.01)


def read_reg(addr):
    packet = bytes([0xBB, addr & 0xFF, 0x55])
    ser.write(packet)

    resp = ser.read(4)

    if len(resp) != 4:
        print("Read timeout")
        return None

    if resp[0] != 0xCC or resp[1] != addr:
        print("Invalid response:", list(resp))
        return None

    return resp[2]


# -----------------------------
# Test Sequence
# -----------------------------

print("Enable remote mode")
write_reg(0x00, REMOTE)
time.sleep(0.05)

ctrl_val = read_reg(0x00)
print("CTRL =", ctrl_val)


print("Setting exposure to 1000 us")

exp = 1000
write_reg(0x01, exp & 0xFF)
write_reg(0x02, (exp >> 8) & 0xFF)

time.sleep(0.05)

exp_l = read_reg(0x01)
exp_h = read_reg(0x02)

print("Exposure readback:", (exp_h << 8) | exp_l)


print("Trigger start")

# Ensure start bit low first
write_reg(0x00, REMOTE)
time.sleep(0.02)

# Rising edge
write_reg(0x00, REMOTE | START)

time.sleep(0.05)

ctrl_after = read_reg(0x00)
print("CTRL after start =", ctrl_after)

print("Done.")