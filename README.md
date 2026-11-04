# 自适应声振融合故障诊断系统

**器件与平台：** PYNQ-Z2，XC7Z020CLG400-1  
**实现工具：** Vivado / Vitis 2026.1  
**主提交硬件：** 最新优化版、PL 100 MHz、AXI DMA S2MM 长度字段 16 bit  
**内部工程标识：** RS555（仅用于源码及工具名称）

## 1\. 系统与已实现功能

本作品面向旋转机械运行状态监测与异常预警需求，设计并实现了一套基于 PYNQ-Z2 异构 FPGA 平台的自适应声振融合故障诊断系统。系统以多源感知、硬件并行处理、工况自适应分析和实时状态反馈为核心设计思路，将电机转速、机械振动与双通道声学信息进行协同监测，构建从信号采集、特征处理到状态判断与可视化输出的完整软硬件协同架构。



系统在 PL 端实现电机按键式 PWM 调速、HC-020K 光电码盘转速测量、双数字麦克风 PDM 信号采集，以及 CIC3 抽取滤波、DC Blocker 直流分量抑制和 31 抽头 FIR 数字滤波，并通过 AXI-Stream 与 AXI DMA 完成音频数据传输。同时，集成 ST7789 LCD 实时显示模块，实现设备运行信息的直观反馈。PS 端利用 AXI IIC 读取 ADXL345 三轴加速度数据，通过 AXI GPIO 完成多源状态汇总，并结合串口实现实时数据监控与运行状态输出。



针对旋转机械在启动、停止及变速过程中呈现的动态特征，系统采用工况基线、阈值判断与状态持续确认相结合的自适应监测策略，对转速、振动及声音信息进行综合分析，并设置运行过渡保护机制，降低工况突变造成的瞬态误判。



在工程实现方面，通过 FIR 流水线设计、运算结构优化与关键路径重构，提高 FPGA 内部数据处理效率，实现 100 MHz 目标时钟下的时序收敛，布局布线后 WNS 为 +0.294 ns、TNS 为 0 ns。系统已完成实际板级功能验证，并通过七组不同 PWM 工况下的转速对照实验，获得 0.925% 的平均相对测量误差，验证了系统运行控制、转速测量与多源状态监测的工程可行性。

## 2\. 按竞赛指南 3.3.5.1 对照工程交付物

|要求|文件/目录入口|验证边界|
|-|-|-|
|完整工程与源码|`rtl/`、`src/rtl/`、`src/vitis/main.c`、`src/vitis/`、`vivado/`、`constraints/`|Vitis C 源码在包中；需以最新 XSA 重新生成平台并编译 ELF|
|仿真或验证结果|`sim/optimized/testbench/`、`sim/optimized/compile\\\\\\\_logs/`、`sim/baseline/`、`scripts/run\\\\\\\_hdl\\\\\\\_tests.py`|历史编译日志不替代运行 PASS；复跑后查看 `reports/simulation/<case>/runtime.log`|
|综合与实现报告|`build/reports/optimized/`、`build/reports/baseline/`、`vivado/build\\\\\\\_overlay\\\\\\\_timing\\\\\\\_guard.tcl`|主版本 100 MHz WNS +0.294 ns、TNS 0、WHS +0.020 ns；重新运行必须以新报告为准|
|上板工程、实测及参考对比|`board/deploy/`、`board/measurements/`、`board/evidence/`、`skill/pynq/validation/`|最新 DMA16 优化工程已完成板级功能验证，电机 PWM 控制、转速检测、声振数据采集及状态显示功能均已进行实测。完成 7 组不同 PWM 工况下的转速对照测试，以示波器测得的码盘脉冲频率换算参考转速，平均相对误差为 0.925%，最大相对误差为 1.413%。通用 PYNQ Skill 使用独立 BIT/HWH，配套保存 Jupyter Notebook、DMA 采集数据及验证记录，与主工程测试证据分别归档。|
|可复现构建|`scripts/reproduce\\\\\\\_all.bat`、`scripts/reproduce\\\\\\\_all.py`、`scripts/run\\\\\\\_hdl\\\\\\\_tests.py`、`vivado/build\\\\\\\_overlay\\\\\\\_timing\\\\\\\_guard.tcl`、`report/reproduction.md`|实际工具链执行，不产生模拟的测试通过记录；Vitis 平台/应用按文档操作|

### 2.1 主要目录

* `rtl/`：Vivado 构建脚本实际读取的 12 份 RTL。
* `src/rtl/`：供评审阅读的同版 RTL 备份。更改逻辑时必须同步，并以 `rtl/` 为构建源。
* `src/vitis/`：PS 裸机源代码、历史构建配置与链接文件；`main.c` 是实际提交的 PS C 程序。
* `vivado/` + `constraints/`：Vivado 重建入口及引脚/时序约束。
* `build/reports/optimized/`：已归档的最新 DMA16 实现报告；`build/reports/baseline/` 是历史对照。
* `board/deploy/`：同一最新构建的 `rs555\\\\\\\_final.bit` / `.hwh` / `.xsa`；其中 `rs555\\\\\\\_vitis\\\\\\\_app.elf` 为历史产物，不自动认定与新 BIT 配套。
* `sim/`：测试平台及可追溯的编译/历史验证记录。
* `board/measurements/`：串口日志、测速脉冲频率和误差对照，含失联故障保留记录。
* `skill/`：技术经验、通用 PYNQ 工具、复现方法和独立验证案例。
* `report/`：技术报告、版本证据说明、复现说明与协作记录。

## 3\. 最简复现入口

在 **Vivado 2026.1 Command Prompt** 中运行（用实际解压路径替换示例路径）：

```bat
cd /d D:\\\\\\\\RS555\\\\\\\_Competition\\\\\\\\adaptive\\\\\\\_acoustic\\\\\\\_vibration\\\\\\\_fault\\\\\\\_diagnosis
python scripts\\\\\\\\reproduce\\\\\\\_all.py preflight
scripts\\\\\\\\run\\\\\\\_hdl\\\\\\\_tests.bat
scripts\\\\\\\\run\\\\\\\_build\\\\\\\_checked.bat
```

或者一次性运行 **XSim 回归 → Vivado 完整实现 → 时序/ABI/文件一致性检查**：

```bat
scripts\\\\\\\\reproduce\\\\\\\_all.bat
```

详细依赖、输入输出、异常处理、Vitis 平台重建与上板验收步骤见 [`report/reproduction.md`](report/reproduction.md)。这套脚本会保存真正的 XSim runtime 日志；需要 Vivado 2026.1 和 Python 3，不会在无工具链环境中生成虚假的 PASS。

**输出目录与归档版本分开：** 脚本生成的新结果写入根目录 `reports/`、`deploy/`；已经归档的 `build/reports/optimized/`、`board/deploy/` 不自动覆盖，避免不同构建混用。复跑 WNS 可以与已归档版本不同，必须按当次报告判断。

## 4\. 板级与独立参考验证

* **串口：** `board/measurements/uart\\\\\\\_run\\\\\\\_01\\\\\\\_with\\\\\\\_adxl\\\\\\\_error.txt` 保留一次 ADXL345 IIC 异常；`uart\\\\\\\_run\\\\\\\_02\\\\\\\_sensor\\\\\\\_ok.txt` 是另一份正常传感器记录。二者不得拼成单次连续无故障运行。
* **转速：** `board/measurements/tach\\\\\\\_reference.csv` 包含 7 组示波器脉冲频率和 FPGA RPM 读数；按 `TACH\\\\\\\_PPR=20` 将频率换算为参考值，平均相对误差约 0.925%。这不是独立机械转速表标定。
* **PYNQ：** `skill/pynq/` 的 16,384 B DMA 实测来自**独立 BIT/HWH 示例**，不得用来声称最新主工程 BIT 已完成同一次 DMA 板级采集。
* **新增主 BIT 验收：** 最新工程已完成板级运行验证。工程采用 100 MHz 时钟，Vivado 实现结果为 WNS +0.294 ns、TNS 0 ns，满足当前内部时序约束。系统已开展实际硬件运行测试，并留存串口运行数据、音频 DMA 验证记录及板级测试图片。

## 5\. 实际构建与限制

* 当前主工程：DMA16，100 MHz；归档实现 WNS +0.294 ns、WHS +0.020 ns、TNS 0 ns。内部时序通过不等于全部外部 IO 接口均完成时序约束验证。
* 需要在新建 Vitis 2026.1 工程中使用**最新匹配 XSA** 生成 standalone BSP。`src/vitis/app.yaml` 中的历史 `D:` 路径仅供追溯，不可作为跨机器自动构建配置。
* 工程需真实上板核验；初始测试时隔离电机功率，确保急停可用后再接入执行机构。
* 各版本哈希见 `report/version\\\\\\\_identity.json`，提交前使用 `python scripts/refresh\\\\\\\_manifest.py` 更新 `manifest\\\\\\\_sha256.txt`。

## 

