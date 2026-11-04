# Independent AXI GPIO project — offline reuse verification

## Purpose

This case checks whether `make_contract.py` and `overlay_audit.py` can work on an FPGA design unrelated to the RS555 acoustic/vibration diagnostic project. It uses an independently generated Vivado HWH for Zynq PS + AXI GPIO. This is an **offline interface-metadata check**, not an on-board GPIO functional test.

## Hardware metadata from the supplied HWH

- AXI GPIO instance: `axi_gpio_0`, `xilinx.com:ip:axi_gpio:2.0`
- `C_GPIO_WIDTH=8`, `C_IS_DUAL=0`
- Mapped address: `0x41200000` through `0x4120ffff`
- HWH includes four modules; the contract intentionally constrains the AXI GPIO module.

## Reproduce

Run the commands from the parent `skill/` directory (Python >= 3.9):

```bash
python tools/make_contract.py validation/gpio_demo/gpio_demo.hwh --out /tmp/gpio_contract_recreated.json
python tools/overlay_audit.py validation/gpio_demo/gpio_demo.hwh --contract validation/gpio_demo/gpio_contract.json --report /tmp/gpio_audit_pass_recreated.json
python tools/overlay_audit.py validation/gpio_demo/gpio_demo.hwh --contract validation/gpio_demo/gpio_contract_bad.json --report /tmp/gpio_audit_fail_recreated.json
```

The final command is **expected to fail** (exit code 2), because the deliberately altered contract requests `C_GPIO_WIDTH=16` but the HWH records `8`.

## Observed results

- Original generated contract: `RESULT: PASS` (four HWH modules, three unconstrained modules noted).
- Deliberately corrupted contract: `RESULT: FAIL` with `axi_gpio_0: C_GPIO_WIDTH actual='8', expected='16'`.
- Evidence: `gpio_audit_pass.json`, `gpio_audit_fail.json`, `gpio_contract.json`, `gpio_contract_bad.json`, and unmodified `gpio_demo.hwh`.

## Scope and limitations

The first contract is generated from the same HWH that is audited, so its PASS result alone is a self-consistency check; the deliberate parameter-mismatch test demonstrates detection of a known discrepancy. An independent reviewed baseline or a changed HWH revision would give stronger regression evidence. This test does not show synthesis or timing closure, bitstream compatibility, electrical GPIO behavior, or cross-board operation. The HWH was supplied from a separate Vivado design and the source Vivado project is not bundled here.
