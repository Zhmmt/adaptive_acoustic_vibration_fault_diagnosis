# XSA/HWH 软件接口契约核对

适用：PL RTL 优化后，拟沿用既有 Vitis C 程序或裸机 ELF。方法：对比 HWH 中 AXI 外设基址/高址、GPIO 宽度、AXI DMA Stream 位宽与收发模式；随后检查软件宏、状态字布局和板级动作。

```text
python skill/tools/hwh_contract.py old_design.hwh new_design.hwh
```

RS555 样例保留 `axi_dma_audio=0x40400000`、`axi_gpio_ctrl=0x41200000`、`axi_gpio_status0/1/2=0x41210000/0x41220000/0x41230000`、`axi_gpio_adxl_sw=0x41240000`、`axi_iic_adxl=0x41600000`。这些是本项目示例，不能硬编码用于陌生项目。

**限制**：静态参数比较不是 CPU/DDR 寄存器行为或电气等价证明；即使 HWH 对比通过，也应对现有 ELF 执行 UART、IIC、PWM、按键、LCD、DMA 回归。
