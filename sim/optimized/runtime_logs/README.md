# RS555 优化工程 — XSim 仿真运行日志

## 1. 说明

本目录保存 RS555 优化工程的 **5 项 HDL 功能仿真运行日志**，用于核查相应测试平台（testbench）的实际运行输出。日志文件由 Vivado Simulator（XSim）生成，不是仅有语法分析信息的编译日志。

本次运行环境：**Windows + Vivado / XSim 2022.2**。原工程文档中提到的 Vivado 2026.1 是另一版本的工具环境；请勿将两者混写成同一次验证。

## 2. 日志和验收标记

| 运行日志 | 测试内容 | 日志中应核对的 PASS 标记 |
| --- | --- | --- |
| `fir31_sim.log` | FIR31 流水线滤波器 | `FIR31_PIPELINE_TEST_PASS` |
| `lcd_sim.log` | LCD 转速 BCD 显示 | `LCD_RPM_BCD_TEST_PASS` |
| `tach_eq_sim.log` | 转速计算逻辑等价性 | `TACH_EQ_PASS` |
| `dc_sim.log` | DC Blocker 稀疏采样测试 | `DC_BLOCKER_SPARSE_TEST_PASS` |
| `stereo_sim.log` | 双麦克风音频集成 | `AUDIO_INTEGRATION_TEST_PASS` |

请以每份日志的**实际内容**为最终依据：检查是否有上述对应标记、是否出现 `$finish` 等正常结束信息，以及是否存在 `ERROR`、`FATAL`、`FAIL` 等失败记录。文件存在不等于测试自动通过。

## 3. 复现方法

在已正确配置 Vivado 2022.2 环境的 Windows 命令提示符中，进入**工程根目录**后执行：

```bat
scripts\run_hdl_tests.bat
```

提交的脚本应为修订版，使用 `call xvlog`、`call xelab work.<测试顶层>`、`call xsim` 顺序执行五项测试，并在测试未通过时返回错误；不能只进行编译就输出 `ALL_SIM_TESTS_PASS`。

XSim 原始运行日志生成在：

```text
reports/simulation/*_sim.log
```

归档位置（本目录）：

```text
sim/optimized/runtime_logs/
```

如脚本没有自动复制日志，可在工程根目录执行：

```bat
copy /Y reports\simulation\*_sim.log sim\optimized\runtime_logs\
```

## 4. 验证范围与限制

这些日志证明的是**相应 HDL testbench 所覆盖的功能**，不等于 FPGA 实物上板验证，也不等于重新完成综合、布局布线或 100 MHz 时序收敛。时序结果应查阅 `reports/optimized/` 中对应实现版本的报告；开发板功能应单独实测。

随最终工程提交时，请同时保留实际运行日志、对应版本的 `scripts/run_hdl_tests.bat`、`rtl/` 和 `sim/testbench/` 源文件，以便复现。
