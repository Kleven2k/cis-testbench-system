import os
import sys
import subprocess
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SIM_DIR   = Path(__file__).resolve().parent

SOURCES = [
    REPO_ROOT / "hdl" / "rtl" / "uart" / "uart_tx.sv",
    REPO_ROOT / "hdl" / "rtl" / "uart" / "uart_rx.sv",
    SIM_DIR   / "uart_loopback_tb_wrapper.sv",
]

SIM_BUILD = SIM_DIR / "sim_build"
VVP_FILE  = SIM_BUILD / "sim.vvp"


def compile():
    print("\n=== Compiling ===\n")
    SIM_BUILD.mkdir(exist_ok=True)

    cmd = [
        "iverilog", "-g2012",
        "-o", str(VVP_FILE),
        "-s", "uart_loopback_tb_wrapper",
    ] + [str(s) for s in SOURCES]

    r = subprocess.run(cmd, cwd=REPO_ROOT)
    if r.returncode != 0:
        print("COMPILE FAILED")
        sys.exit(1)


def run(testcase=None):
    print("\n=== Running simulation ===\n")

    cocotb_config = shutil.which("cocotb-config")
    if cocotb_config is None:
        print("ERROR: cocotb-config not found — is cocotb installed?")
        sys.exit(1)

    libpython    = subprocess.check_output([cocotb_config, "--libpython"], text=True).strip()
    python_home  = str(Path(libpython).parent)
    cocotb_libs  = Path(subprocess.check_output([cocotb_config, "--lib-dir"], text=True).strip())

    env = os.environ.copy()
    env["PYTHONHOME"]          = python_home
    env["PYGPI_PYTHON_BIN"]    = sys.executable
    env["PYTHONPATH"]          = str(SIM_DIR)
    env["COCOTB_TEST_MODULES"] = "test_uart"
    env["PATH"]                = python_home + os.pathsep + env.get("PATH", "")

    if testcase:
        env["COCOTB_TEST_FILTER"] = testcase

    cmd = [
        "vvp",
        "-M", str(cocotb_libs),
        "-m", "cocotbvpi_icarus",
        str(VVP_FILE),
    ]
    subprocess.run(cmd, env=env, cwd=SIM_DIR)


if __name__ == "__main__":
    testcase = sys.argv[1] if len(sys.argv) > 1 else None
    compile()
    run(testcase)
