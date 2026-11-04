# 自适应声振融合故障诊断系统

**器件与平台：** PYNQ-Z2，XC7Z020CLG400-1  
**实现工具：** Vivado / Vitis 2026.1  
**主提交硬件：** 最新优化版、PL 100 MHz、AXI DMA S2MM 长度字段 16 bit  
**内部工程标识：** RS555（仅用于源码及工具名称）

## 1\. 系统与已实现功能

本工程完成电机 PWM 按键控制、光电码盘 RPM 测量、双数字麦克风 PDM 输入及 CIC3/DC Blocker/FIR31 处理、AXI-Stream 音频帧输出、ST7789 状态显示，以及 PS 端 AXI IIC 读取 ADXL345、AXI GPIO 状态汇总和串口监视。设备状态检测采用工况基线、阈值及状态确认策略。**未提供完成 FFT 频谱诊断、机器学习故障分类或故障分类准确率标定的证据**，不以此作为已完成成果。

## 2\. 按竞赛指南 3.3.5.1 对照工程交付物

|要求|文件/目录入口|验证边界|
|-|-|-|
|完整工程与源码|`rtl/`、`src/rtl/`、`src/vitis/main.c`、`src/vitis/`、`vivado/`、`constraints/`|Vitis C 源码在包中；需以最新 XSA 重新生成平台并编译 ELF|
|仿真或验证结果|`sim/optimized/testbench/`、`sim/optimized/compile\_logs/`、`sim/baseline/`、`scripts/run\_hdl\_tests.py`|历史编译日志不替代运行 PASS；复跑后查看 `reports/simulation/<case>/runtime.log`|
|综合与实现报告|`build/reports/optimized/`、`build/reports/baseline/`、`vivado/build\_overlay\_timing\_guard.tcl`|主版本 100 MHz WNS +0.294 ns、TNS 0、WHS +0.020 ns；重新运行必须以新报告为准|
|上板工程、实测及参考对比|`board/deploy/`、`board/measurements/`、`board/evidence/`、`skill/pynq/validation/`|7 组测速参考误差约 0.925%（平均值）；PYNQ 案例 BIT 与主 BIT 不同；新主 BIT 的全功能板测需单独记录|
|可复现构建|`scripts/reproduce\_all.bat`、`scripts/reproduce\_all.py`、`scripts/run\_hdl\_tests.py`、`vivado/build\_overlay\_timing\_guard.tcl`、`report/reproduction.md`|实际工具链执行，不产生模拟的测试通过记录；Vitis 平台/应用按文档操作|

### 2.1 主要目录

* `rtl/`：Vivado 构建脚本实际读取的 12 份 RTL。
* `src/rtl/`：供评审阅读的同版 RTL 备份。更改逻辑时必须同步，并以 `rtl/` 为构建源。
* `src/vitis/`：PS 裸机源代码、历史构建配置与链接文件；`main.c` 是实际提交的 PS C 程序。
* `vivado/` + `constraints/`：Vivado 重建入口及引脚/时序约束。
* `build/reports/optimized/`：已归档的最新 DMA16 实现报告；`build/reports/baseline/` 是历史对照。
* `board/deploy/`：同一最新构建的 `rs555\_final.bit` / `.hwh` / `.xsa`；其中 `rs555\_vitis\_app.elf` 为历史产物，不自动认定与新 BIT 配套。
* `sim/`：测试平台及可追溯的编译/历史验证记录。
* `board/measurements/`：串口日志、测速脉冲频率和误差对照，含失联故障保留记录。
* `skill/`：技术经验、通用 PYNQ 工具、复现方法和独立验证案例。
* `report/`：技术报告、版本证据说明、复现说明与协作记录。

## 3\. 最简复现入口

在 **Vivado 2026.1 Command Prompt** 中运行（用实际解压路径替换示例路径）：

```bat
cd /d D:\\RS555\_Competition\\adaptive\_acoustic\_vibration\_fault\_diagnosis
python scripts\\reproduce\_all.py preflight
scripts\\run\_hdl\_tests.bat
scripts\\run\_build\_checked.bat
```

或者一次性运行 **XSim 回归 → Vivado 完整实现 → 时序/ABI/文件一致性检查**：

```bat
scripts\\reproduce\_all.bat
```

详细依赖、输入输出、异常处理、Vitis 平台重建与上板验收步骤见 [`report/reproduction.md`](report/reproduction.md)。这套脚本会保存真正的 XSim runtime 日志；需要 Vivado 2026.1 和 Python 3，不会在无工具链环境中生成虚假的 PASS。

**输出目录与归档版本分开：** 脚本生成的新结果写入根目录 `reports/`、`deploy/`；已经归档的 `build/reports/optimized/`、`board/deploy/` 不自动覆盖，避免不同构建混用。复跑 WNS 可以与已归档版本不同，必须按当次报告判断。

## 4\. 板级与独立参考验证

* **串口：** `board/measurements/uart\_run\_01\_with\_adxl\_error.txt` 保留一次 ADXL345 IIC 异常；`uart\_run\_02\_sensor\_ok.txt` 是另一份正常传感器记录。二者不得拼成单次连续无故障运行。
* **转速：** `board/measurements/tach\_reference.csv` 包含 7 组示波器脉冲频率和 FPGA RPM 读数；按 `TACH\_PPR=20` 将频率换算为参考值，平均相对误差约 0.925%。这不是独立机械转速表标定。
* **PYNQ：** `skill/pynq/` 的 16,384 B DMA 实测来自**独立 BIT/HWH 示例**，不得用来声称最新主工程 BIT 已完成同一次 DMA 板级采集。
* **新增主 BIT 验收：** 若要宣称最新 DMA16 主 BIT 的完整上板验证，需另存新 BIT/ELF 组合、原始日志、音频 DMA 和实测截图。

## 5\. 实际构建与限制

* 当前主工程：DMA16，100 MHz；归档实现 WNS +0.294 ns、WHS +0.020 ns、TNS 0 ns。内部时序通过不等于全部外部 IO 接口均完成时序约束验证。
* 需要在新建 Vitis 2026.1 工程中使用**最新匹配 XSA** 生成 standalone BSP。`src/vitis/app.yaml` 中的历史 `D:` 路径仅供追溯，不可作为跨机器自动构建配置。
* 工程需真实上板核验；初始测试时隔离电机功率，确保急停可用后再接入执行机构。
* 各版本哈希见 `report/version\_identity.json`，提交前使用 `python scripts/refresh\_manifest.py` 更新 `manifest\_sha256.txt`。

## 

