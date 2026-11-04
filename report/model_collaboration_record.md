# 工程技术问题协作与纠错记录

## 记录范围与证据原则

本记录围绕《自适应声振融合故障诊断系统》的**疑难技术问题定位、建议检验和失败纠错**，不以“一次生成完整工程”作为案例。下列“原始问题表达”来自已保留的交互文字或截图；“处理方案”是技术摘要，**并非冒充模型回答逐字原文**。涉及成绩的数字以原始 Vivado、XSim、串口或 Notebook 文件为准。比赛要求提交大模型交互的真实提示词、模型回答及自我纠错轨迹，应将原始聊天导出另置归档，并在提交前进行身份脱敏。

## 案例 1：已能上板的工程为什么仍有严重时序违例？

**原始问题表达：** “可是我之前发给你的vivado 工程已经是上板跑成功的呀，我们已经录了视频”；提供 `[Timing 38-282]` 和 Setup WNS -39.029 ns、TNS -2462.099 ns、346 个失败终点的 Vivado 窗口。

**困难点：** 板级功能偶然运行成功不能替代时钟约束验收；需要区分过长组合逻辑和错误约束，不可直接放宽时钟要求。最初 FIR31 多级串行算术路径，后续瓶颈陆续迁移至 LCD、测速及有效位高扇出网络。

**方案与纠错摘要：** 按布线后 `report_timing_summary` 和 `report_timing` 中起点/终点、逻辑/布线占比定位；优先进行保持接口语义的 RTL 分级/寄存，再用完整仿真检测数据与 valid 延迟，最后重新实现。并要求保留原 100 MHz 约束。

**可核查证据：** `build/reports/baseline/timing_summary.rpt`；`build/reports/optimized/timing_summary.rpt`；`build/reports/optimized/worst_paths.rpt`；`data/timing_evolution.csv`。最终最新 DMA16 实现 WNS +0.294 ns、TNS 0 ns；其余接口约束边界见 `check_timing.rpt`。

**提炼的通用方法：** 路由时序失败的起点/终点分类、流水化后的仿真门禁、不要用视频成功代替时序收敛。

## 案例 2：FIR31 初次流水线修改出现 VALID_FAIL

**原始证据与问题：** XSim 提示 `Fatal: VALID_FAIL idx=0 got=1 expected=0`，用户展示 `tb_fir31_pipeline` 运行界面、有效位流水寄存器以及源码文件检查结果。

**困难点：** FIR 数值计算、输出保持和有效位延迟需要同时对应。Vivado 工程还可能引用外部 `imports/` 中的旧 `fir31.v`，使实际仿真模块不是期望的版本。

**处理方案与纠错摘要：** 对比 `out_valid` 与 testbench 的 6 周期期望；检查 `get_files -all *fir31.v` 是否有两份同名 RTL；排除旧副本后重新编译并完整运行 XSim，不能仅凭 `elaborate completed` 判断通过。

**证据：** 早期 `VALID_FAIL` 截图、`fir31.v` 文件引用输出、`sim/optimized/testbench/tb_fir31_pipeline.v`；后续控制台 `FIR31_PIPELINE_TEST_PASS checked=369 latency_cycles=6` 记录。此 PASS 属于相应时刻的仿真，不自动覆盖新的代码版本。

**通用方法：** 先核对仿真真正编译的源文件，再核对延迟对齐及数据正确性；将每个仿真 case 使用独立编译目录。

## 案例 3：改进某条关键路径后，新的最差路径继续恶化

**原始问题表达：** 提交从 LCD `snap_rpm_reg→pix_reg`、到测速 `rpm1→rpm_reg`、再到 `audio0/dc0/y_prev_reg→dout_reg` 的不同时期时序截图，询问“结果怎么样”“优化工程，保证时序通过，指标漂亮，不改变其他设置，可以用原版vitis”。

**困难点：** FPGA 优化会迁移最差路径；不能只改当前第一名而忽略其余失败终点。寄存器数和 DSP 使用量增加，也应给出真实资源代价。

**处理方案与纠错摘要：** 逐阶段提取路径组、Slack、逻辑层数和 net delay；采用 LCD BCD 预计算、测速算术简化、DC Blocker 分级运算、FIR 流水线后，继续仿真与 routed 检查。关键接口优先保持一致，并在 HWH 比较 PS 可见寄存器映射。

**证据：** 不同阶段时序截图、`build/reports/optimized/` 及 `data/performance_metrics.json`。最终主工程 LUT 4329、FF 6220、DSP 84；不能表述为所有片上资源均减少。

**通用方法：** 每次迭代独立保存最差路径、资源占用和验证状态，避免只看单次 WNS。

## 案例 4：同名 RTL 文件冲突和 Tcl/CMD 工作目录混用

**原始问题与界面：** 用户提交 `get_files -all *fir31.v` 返回两条路径的结果，以及 Vivado Tcl Console 中 `cd /d D:\RS555_Competition\...` 出现 `wrong # args: should be "cd ?dirName?"`。

**困难点：** Windows CMD 的 `cd /d` 并非 Tcl 的合法写法；Vivado fileset 还可能引用历史路径副本，导致源码版本错配。

**处理方案与纠错摘要：** 在 CMD 使用 `cd /d D:\...`；在 Vivado Tcl 使用 `cd {D:/...}` 或 `source` 绝对 Tcl 路径。将仿真文件列表显式化，并在复现脚本中通过脚本所在位置计算工程根目录。

**证据：** Tcl 错误截图、检查 `get_files` 输出、`vivado/build_overlay_timing_guard.tcl` 中基于 `[info script]` 的 root 定位，以及本次提交的 `scripts/run_hdl_tests.py`。

**通用方法：** 明确区分 Shell 语法与 Tcl 语法；禁止在构建脚本中暗中使用旧工作区路径。

## 案例 5：4096 个 32-bit 数据字与 DMA14 长度字段冲突

**原始问题表达：** “skill必须16吗”“不是这不失败了吗”“那我交代码要交哪版，skill可以和我的代码不一样吗”。Notebook 显示 `C_SG_LENGTH_WIDTH=14`、`Frame bytes: 16384`、`DMA max bytes: 16383`、`Frame fits DMA: False`，断言直接失败。

**困难点：** 单次完整帧的字节数恰好超过 DMA14 的长度上限 1 字节；删除 `assert` 并不能改变硬件容量。另有独立 PYNQ DMA16 已实测样例，不能证明新的主 BIT 一定完成该实验。

**处理方案与纠错摘要：** 先进行 HWH 能力检查，若不足则停止完整帧 DMA；独立配置 DMA16 后，重新实现并保留本次生成的 BIT/HWH/XSA。审查 TLAST、cache 和 DMA `IOC/IDLE` 等运行状态。主工程 DMA16 和 Skill 案例 DMA16 用文件哈希区分。

**证据：** Jupyter 报错截图、`skill/pynq/validation/pynq_z2/` Notebook 和 BIN；`report/version_identity.json`、`board/deploy/` 哈希。主工程最新实现指标与 PYNQ 样例的板端验证不属于同一版。

**通用方法：** DMA 长度预检查、失败边界显式报告、流帧结束条件和硬件文件指纹配套。

## 案例 6：Vitis 串口不输出、旧 ELF 与新 BIT 版本混淆

**原始问题表达：** “为什么一直卡在这”“串口输出显示是main.c控制吗，我没改main.c怎么变了”。Vitis 调试截图显示 `Opening COM6: Access denied`。

**困难点：** 关闭调试会话、串口占用、实际下载的 ELF 与编辑器中的 `main.c` 不一致，是不同故障类型；即使 C 字符串不变，RTL 输出的寄存器数值也可能变化。

**处理方案与纠错摘要：** 区分 PS 程序执行状态、UART 串口占用和文件版本；查看 Debug configuration 的 ELF 路径以及板上 BIT 版本；串口由一个进程独占，关闭其他 COM6 终端后再记录。

**证据：** Vitis 调试与 COM6 截图、`src/vitis/main.c`、`board/deploy/rs555_vitis_app.elf` 和 `board/measurements/` 串口日志。历史 ELF 是归档参考，不能作为最新主 BIT 的完整回归证明。

**通用方法：** 用 BIT/ELF SHA-256 锁定一次实验，避免版本漂移造成伪故障。

## 案例 7：ADXL345 在 120 秒运行过程中通信失败

**原始证据：** 串口日志出现 `ADXL345 XYZ read failed`、`Sensor=ERROR`、`Vib=0`；后续另一次记录中 `Sensor=OK`。

**困难点：** 电机负载、I²C 接触、电平、供电或干扰均可能影响读数，但仅凭日志无法唯一确定失效原因。

**处理方案与纠错摘要：** 保留首次异常日志，检查 SCL/SDA、电源和公共地、I²C 初始化；用不同次独立日志表示传感器正常记录，不将两个时段拼接成一次连续无故障测试。

**证据：** `board/measurements/uart_run_01_with_adxl_error.txt`、`uart_run_02_sensor_ok.txt`。没有证据证明具体物理根因已消除时，不写“永久解决”。

**通用方法：** 失败数据同样作为真实验证记录；错误可复现、复测与问题关闭需要独立证据。

## 从实际问题提炼到技能包

上述案例对应 `skill/timing/`、`skill/interface/`、`skill/verification/`、`skill/pynq/`：关键路径诊断与门禁、fileset/接口契约检查、XSim 回归、PYNQ Overlay/HWH 与 DMA 预检及错误处理。跨题目适用场景包括风机、水泵、输送机械和通用 AXI-Stream 数据采集工程，需替换目标器件、接口契约及数据格式，并重新验证。

## 原始对话证据的提交边界

此文件仅是**可溯源技术事件整理**，不是逐字交互转录。为完整满足赛事“提示词、模型回答、自我纠错轨迹”的要求，按真实聊天导出的原文建立附件索引，不得将本摘要写作原始模型逐字回答，也不得虚构交互：

| 交互主题 | 原始证据建议文件名 | 当前状态 |
|---|---|---|
| FIR31 `VALID_FAIL` 与重复源 | `report/chat_evidence/fir31_debug_original.pdf` | 待附原始导出 |
| Vivado WNS -39 ns 至 DMA16 routed 通过 | `report/chat_evidence/timing_debug_original.pdf` | 待附原始导出 |
| DMA14/16 Notebook 断言 | `report/chat_evidence/dma_debug_original.pdf` | 待附原始导出 |
| Vitis COM6/ELF 问题 | `report/chat_evidence/vitis_debug_original.pdf` | 待附原始导出 |
| ADXL345 上板失联和复测 | `report/chat_evidence/board_debug_original.pdf` | 待附原始导出 |

原始交互建议仅做个人、学校、账号标识脱敏，并保留信息顺序与实际技术内容。相关截图可直接按原始文件名归档，但不能冒充工具自动生成或真实板级测试未做过的记录。
