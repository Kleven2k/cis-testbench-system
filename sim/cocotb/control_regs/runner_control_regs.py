"""
Runner for control_regs cocotb tests using Icarus Verilog.

Usage:
    python runner_control_regs.py                        # run all tests
    python runner_control_regs.py test_reset_defaults    # run one test
"""

import os
import sys
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SIM_DIR   = Path(__file__).resolve().parent

SOURCES = [
    REPO_ROOT / "hdl" / "rtl" / "control" / "control_regs.sv",
    SIM_DIR   / "control_regs_tb_wrapper.sv",
]

SIM_BUILD = SIM_DIR / "sim_build"
VVP_FILE  = SIM_BUILD / "sim.vvp"


def compile():
    print("\n=== Compiling ===\n")
    SIM_BUILD.mkdir(exist_ok=True)

    cmd = [
        "iverilog", "-g2012",
        "-o", str(VVP_FILE),
        "-s", "control_regs_tb_wrapper",
    ] + [str(s) for s in SOURCES]

    r = subprocess.run(cmd, cwd=REPO_ROOT)
    if r.returncode != 0:
        print("COMPILE FAILED")
        sys.exit(r.returncode)


def run(testcase=None):
    print("\n=== Running simulation ===\n")

    cocotb_config = shutil.which("cocotb-config")
    if cocotb_config is None:
        print("ERROR: cocotb-config not found — install cocotb in your system Python")
        sys.exit(1)

    cocotb_libs   = Path(subprocess.check_output([cocotb_config, "--lib-dir"],    text=True).strip())
    cocotb_python = subprocess.check_output([cocotb_config, "--python-bin"], text=True).strip()
    cocotb_site   = cocotb_libs.parents[1]

    env = os.environ.copy()
    env["PYGPI_PYTHON_BIN"]    = cocotb_python
    env["PYTHONPATH"]          = str(SIM_DIR) + os.pathsep + str(cocotb_site)
    env["COCOTB_TEST_MODULES"] = "test_control_regs"

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
