# 从零复现：RTL 仿真、Vivado 实现、Vitis 软件及板级证据

> 项目：自适应声振融合故障诊断系统；目标器件 XC7Z020CLG400-1；Vivado/Vitis 2026.1。本文中的 PASS 表示工具真实返回且对应日志可查，不能用预先打包的文件冒充本次复现。

## 1. 复现内容与版本界限

主工程包含 `rtl/` 下的最终 RTL、`constraints/overlay.xdc`、`vivado/build_overlay_timing_guard.tcl`，以及 `src/vitis/main.c`。新生成的实现/部署文件写入工程根目录 `reports/optimized/`、`deploy/`。归档的既有版本放在 `build/reports/optimized/`、`board/deploy/`，脚本**不自动覆盖**。归档 DMA16 设计的 WNS +0.294 ns、WHS +0.020 ns、100 MHz 是历史测试结果，而不是每次重建必然得到的数值。

请勿把 `skill/pynq/examples/rs555_case/` 的独立 PYNQ BIT/HWH 和主工程 `board/deploy/` 的 BIT/HWH 混用。两套版本即使都是 DMA16，哈希不同也属于不同的硬件构建。

## 2. 环境准备

1. Windows 10/11，Vivado 2026.1，Vitis Unified IDE 2026.1；Python 3 可由 CMD 使用。项目路径最好使用英文字符，不放入需要特殊授权的系统目录。
2. 解压后必须确认工程根目录同时有 `rtl/`、`sim/optimized/testbench/`、`vivado/`、`constraints/`、`scripts/`、`src/vitis/main.c`。
3. 从开始菜单启动 **Vivado 2026.1 Command Prompt**。可在 CMD 执行 `where vivado`、`where xvlog`、`where xsim`、`python --version`，并确认版本。
4. 如果只能使用普通 CMD，先运行你的安装目录下的 `settings64.bat`，例如 `call "D:\AMD\2026.1\Vivado\settings64.bat"`。此路径仅是示例，不能按机器用户名猜测实际安装路径。

工程自检：

```bat
cd /d D:\RS555_Competition\adaptive_acoustic_vibration_fault_diagnosis
python scripts\reproduce_all.py preflight
python scripts\run_hdl_tests.py --check-only
```

预期输出包含 `SOURCE_PREFLIGHT_PASS` 和 `SOURCE_PATH_CHECK_PASS`。**仅做预检不等于仿真通过**。

## 3. RTL 仿真：独立隔离、实际执行

```bat
scripts\run_hdl_tests.bat
```

实际调用 `scripts/run_hdl_tests.py`，分别为五类测试建立独立工作目录并执行：

| 用例 | 验证内容 | 通过标记 |
|---|---|---|
| `fir31` | 31 抽头 FIR 流水线数据及有效位延迟 | `FIR31_PIPELINE_TEST_PASS` |
| `lcd` | LCD RPM BCD 转换 | `LCD_RPM_BCD_TEST_PASS` |
| `tach_equivalence` | 优化测速与历史参考算术等价性 | `TACH_EQ_PASS` |
| `dc_blocker` | DC 阻断器稀疏有效数据与复位 | `DC_BLOCKER_SPARSE_TEST_PASS` |
| `stereo_stream` | 双麦克风至 AXI-Stream 封帧与反压 | `AUDIO_INTEGRATION_TEST_PASS` |

每个用例分开执行 `xvlog → xelab → xsim -runall`，检查三个进程实际退出码与 XSim `runtime.log` 中的具体通过标记。日志保存于 `reports/simulation/<case>/{compile.log,elaborate.log,runtime.log,*.stdout.txt}`。仅当五项都完成时生成 `reports/simulation/all_sim_tests_pass.txt`。若执行失败，按对应目录中实际输出排查；不能只凭 `sim/optimized/compile_logs/` 的历史编译成功判断功能通过。

说明：每次重新仿真使用各自临时工作目录，避免另一版本留下的 `xsim.dir` 或同名 `fir31.v` 模块污染当前结果。无需修改已归档 RTL。

## 4. Vivado 重建、时序门禁及硬件交付

在完成实际仿真后运行：

```bat
scripts\run_build_checked.bat
```

或者一条命令完成第三、四节：

```bat
scripts\reproduce_all.bat
```

该批处理执行 `scripts/reproduce_all.py`，调用原工程已验证的 `vivado/build_overlay_timing_guard.tcl`，它完成以下操作：

1. 建立 `build/overlay/rs555_overlay_proj`，目标器件 `xc7z020clg400-1`；载入 `rtl/*.v` 与 `constraints/overlay.xdc`。
2. 创建 Zynq PS7、AXI GPIO、AXI IIC、AXI DMA 和 `rs555_system_core`，时钟 `FCLK0=100 MHz`。DMA 为 simple S2MM，`CONFIG.c_sg_length_width {16}`，数据宽度 32 bit，4096 个 32-bit 数据字构成 16,384 B 音频帧。
3. 执行综合和实现，完成 Route 后导出 `timing_summary.rpt`、`worst_paths.rpt`、`utilization.rpt`、`drc.rpt`、`check_timing.rpt`。
4. 读取布线后 Setup/Hold Slack，若存在失败则 Tcl 报错，**不发布新的 BIT/XSA**。满足当前时序约束后生成 Bitstream。
5. 输出同次构建的 `deploy/rs555_final.bit`、`deploy/rs555_final.hwh`、`deploy/rs555_final.xsa`。
6. Python 门禁检查新 `timing_summary.rpt` 的 WNS/TNS/WHS/失败终点、HWH 的 16 位 DMA、XSA 内 BIT/HWH 与 deploy 文件逐字节一致性，并运行 `scripts/check_vitis_abi.py` 比较 AXI 地址及关键参数。

生成物的实际路径：

```text
reports/
  vivado_reproduce.log
  vivado_reproduce.jou
  optimized/
    timing_summary.rpt
    worst_paths.rpt
    utilization.rpt
    clock_utilization.rpt
    drc.rpt
    check_timing.rpt
    timing_gate_result.txt
deploy/
  rs555_final.bit
  rs555_final.hwh
  rs555_final.xsa
```

注意：`reports/` 和 `deploy/` 为此次复现输出；打包时归档报告在 `build/reports/optimized/`，预生成部署文件在 `board/deploy/`，不得将两套混合。新实现的 WNS/TNS 可能与归档结果存在布局差异，请以新日志为准。

如果 Vivado 报 IP 版本变化、BD 自动连接失败、XDC 不匹配、实际时序未达标，应保留工具日志，纠正后重新完整运行。**不能通过降低主频、删除时序约束或忽略失败端点来宣称等价通过**。 `check_timing.rpt` 包含外部输入输出延迟约束的限制，内部 WNS 为正不代表外部接口时序均已验证。

只核验现有新构建文件、不重新运行 Vivado：

```bat
python scripts\reproduce_all.py verify
```

## 5. Vitis 2026.1 软件重建：源码完整，但平台需重新生成

代码包**包含 PS 端完整 C 程序**：`src/vitis/main.c`，同时保留 `src/vitis/CMakeLists.txt`、`UserConfig.cmake`、`app.yaml`、`lscript.ld` 以便追溯。`board/deploy/rs555_vitis_app.elf` 属于历史运行产物，**没有与本次重建的新 BIT 自动完成板级配对验证**。

推荐在 Vitis Unified IDE 中执行：

1. 新建工作区；创建 **Platform Component**，导入第四节生成的 `deploy/rs555_final.xsa`（如果只验证归档主版本，则选择 `board/deploy/rs555_final.xsa`，严禁混用）。
2. 建立 `standalone` 域，处理器选择实际平台中的 `ps7_cortexa9_0`。生成 BSP/platform，确认 `xparameters.h` 里存在 AXI GPIO、DMA 和 `axi_iic_adxl` 对应地址宏。
3. 新建 **Application Component**，选择刚生成的平台与 standalone 域，使用 Empty Application 模板。将 `src/vitis/main.c` 加入 `src/`。按平台自动生成的链接脚本配置应用；如使用归档 `lscript.ld`，必须检查 DDR/内存布局与最新平台相符。
4. 确保 BSP 可用 `xiic.h`、`xuartps.h` 等驱动；在 Vitis 中 Build Application，保存编译输出，获得本次新 ELF。
5. `src/vitis/app.yaml` 仍含上一台电脑的绝对路径，`UserConfig.cmake` 也保留旧工作区相对路径。**不要直接复制这些旧路径来跨机编译**。以新平台自动生成的应用配置为主，归档文件仅供比较设置。不要用旧 ELF 的存在替代本次编译成功。
6. 电机功率断开的安全状态下，编程同版本 BIT，下载新 ELF 并运行；验证 IIC、GPIO 状态、LCD、双麦克风、测速和最终的 4096 字 S2MM 音频帧。检查 `a` 音频采集命令的 DMA 完成状态与数据，而不只看硬件配置位宽。
7. 记录本次配对的 BIT、HWH、XSA、ELF 文件 SHA-256，保存 Vitis 构建日志与串口完整日志。

**不能用 `skill/pynq/` 中另一份已实测 DMA16 BIT/HWH 代替最新主工程的板级验证。**

## 6. 板级运行记录和示波器参考

1. 板卡和传感器检查：电机断电或硬件断开；先验证 3.3 V IIC、输入输出电平、电源及公共地。测试急停/停止逻辑后再启用电机。
2. 串口：使用 `scripts/capture_uart.py`，波特率 115200，关闭 Vitis/PuTTY 对同一 COM 口的占用。运行阶段至少记录停止、启动、稳定运行、调速和停止。将原始记录与本次 BIT/ELF 版本指纹同时保留。
3. 频率基准：HC-020K 计数所用的有效脉冲数 PPR=20，参考值 `RPM_ref = 60*f_pulse/20`。7 组现有对照位于 `board/measurements/tach_reference.csv`，约 0.925% 为样本平均相对误差；不是独立机械转速表精度证明。
4. PWM：示波器保存 PWM 载波 Frequency/Period/Duty 的仪器原始截图/记录。未完成清晰读数前不能把 25 kHz 写成板级独立实测已通过。
5. 传感器：保留出现 `ADXL345 XYZ read failed` 的第一份日志；后一份 Sensor=OK 日志作为不同次实验，绝不能抹去或拼接故障段。
6. 版本记录：每次实验的 BIT/ELF SHA-256、测试日期、示波器探头连接点、配置值和串口输出应一致可溯源。

## 7. 最终归档顺序

按竞赛指南 3.3.5.1 将 `rtl/`、`src/vitis/`、`sim/`、`build/reports/`、`board/`、`vivado/`、`scripts/` 和 `skill/` 一并提交。另上传 `report/design_report.pdf` 作为技术文档。使用：

```bat
python scripts\refresh_manifest.py
```

更新 `manifest_sha256.txt`（文件摘要清单，不是独立强制提交物）。报名网站代码入口要求 RAR <= 200 MB，视频 MP4/H.264 <= 3 分钟、<= 300 MB，签署的官方承诺授权书 PDF 独立上传。报告和附属文件不出现个人/学校/团队身份信息；图片、原始日志、工程属性仍需人工审查。与大模型协作的提示词、回答和纠错轨迹属于赛事要求，详情见 `model_collaboration_record.md`，原始交互导出文件须按真实记录单独归档。

## 8. 常见失败及定位

| 现象 | 优先排查 |
|---|---|
| `xvlog` 不存在 | 没有使用 Vivado 2026.1 Command Prompt；PATH 未配置 |
| `Source file missing` | 是否在完整工程根目录解压；`sim/optimized/testbench/` 是否存在 |
| XSim 出现 `VALID_FAIL` | 确认只有当前 `rtl/fir31.v` 参与编译，检查流水线有效位延迟和 testbench 参考关系 |
| `TIMING_NOT_MET` | 看实际 `reports/optimized/worst_paths.rpt`，针对真实关键路径优化后重新实现 |
| `C_SG_LENGTH_WIDTH=14` | 检查当前 Tcl 与加载的 BIT/HWH 是否为 DMA16 同次构建 |
| `Frame fits DMA: False` | 4096×4=16,384 B，DMA14 最大单次长度 16,383 B；不能绕过检查继续完整帧传输 |
| `VITIS_ABI_MISMATCH` | 不兼容的 HWH/地址或 IP 设置；需要更新平台与 C 端地址映射 |
| `COM6 Access denied` | 串口被 Vitis/PuTTY/其他终端占用；关闭相应串口标签，勿停止运行中的 ARM 程序 |
| `SENSOR_ERROR` | 检查 ADXL345 IIC 电压/接线/噪声及初始化，保留原始错误日志 |
| 生成脚本失败但有旧 BIT | 旧文件不得作为新运行的成功产物，区分 `board/deploy` 与新 `deploy` |
