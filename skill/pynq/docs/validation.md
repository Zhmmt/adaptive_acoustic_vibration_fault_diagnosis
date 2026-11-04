# 测试与证据记录

## 1. 证据目录与核对办法

以下文件原样收录，未人为填造运行输出：

- `validation/pynq_z2/skill_overlay_validation.ipynb`：板端 Jupyter 操作与输出，15 个单元，含旧版限制发现与修复后结果。
- `validation/pynq_z2/rs555_audio_frame.bin`：一次实际 DMA 接收保存的 16,384 字节原始数据。
- `validation/pynq_z2/old_dma14.hwh`：原工程压缩包内 DMA 长度位宽为 14 的旧版硬件描述。
- `validation/pynq_z2/boot_failure.log`：初次无法启动 PYNQ Linux 时保留的原始串口启动日志，包含 ext4 journal 错误。
- `examples/rs555_case/rs555_final.hwh`、`rs555_final.bit`：更新后提供的硬件工件。
- `examples/rs555_case/build_overlay.tcl`、`axis_stereo_frame.v`、`rs555_system_core.v`：用于核对 DMA 长度、帧组织、通道打包及状态寄存器位定义。
- `examples/rs555_case/latest_main.c`：单独提交的较新版裸机 C，不能视为本次 PYNQ Linux 运行的程序。
- `configs/source_evidence.json`：各文件 SHA-256。

文件同名或哈希记录本身**不能证明** BIT 与 HWH 一定来自同一次构建；板上完整接收记录进一步支持本次加载的逻辑能够按约定运行，但不等同于 Vivado 构建日志和实现时序报告。

## 2. 实机检查事实（来源：原始 Notebook）

| 序号 | 检查项 | 已记录结果 | 证明范围 |
|---|---|---|---|
| 1 | 板端环境 | Python 3.8.2、PYNQ 2.7.0，路径 `/home/xilinx/jupyter_notebooks` | PYNQ Linux 的 Python 运行环境可用 |
| 2 | Overlay 元数据 | 7 个 AXI IP 的名称/地址与契约一致，`7 / 7 PASS` | HWH 在板端可解析；不等于 BIT 已下载 |
| 3 | PS 元数据 | `ps7` 无 `phys_addr` | 不应将 PS 条目按普通 AXI MMIO IP 处理 |
| 4 | 配置与 MMIO | `Overlay loaded: True`，读到 `status0=0x0`、`status1=0x00680066`、`status2=0xB1510032`、`motor=0x37` | 已访问 PL 状态寄存器；无电机动作结论 |
| 5 | 动态状态 | 10 次采样 `SoundA=75..129`、`SoundB=78..130`，`DMICAlive=1`、`MotorRUN=0` | 两路显示值动态更新，状态位保持对应值 |
| 6 | PCM 低 16 位计数 | `15620,23658,31702,39743,47784,55824,63866,6371,14411,22453` | 持续增长及 16-bit 回绕，约与标称采样节奏一致 |
| 7 | 旧版帧限制 | 14-bit 长度寄存器最大 16383 B，小于 4096×4=16384 B | 从旧 HWH 观察到的一字节边界问题 |
| 8 | 新版帧限制 | 16-bit 长度寄存器最大 65535 B，`Frame fits: True` | 新版 HWH 能表达该帧长 |
| 9 | 新 DMA 识别 | `Overlay loaded: True`、`DMA driver: DMA`、`S2MM available: True`、`buffer_max_size: 65535` | 驱动识别和新版 BIT 配置检查通过 |
| 10 | DDR 接收 | 初始 `DMASR=0x0`，完成 `DMASR=0x1002`，`transferred=16384`，非零 words=4094 | 一次完整帧 S2MM 到 DDR 接收成功 |
| 11 | PCM 分拆 | 4096 words；A 区间 -143..0，B 区间 -147..1 | 原始字节可按双有符号 16-bit 解码 |

记录中 PYNQ 对 `axi_iic_adxl` 的版本发出警告：HWH IP 类型 `axi_iic:2.1`，内置驱动匹配 `axi_iic:2.0`。当前资料未体现此环境下通过 Python 访问 ADXL345 的验证，不得把警告视作驱动功能已通过。

### 完成状态 `0x1002` 的解释

按 DMA S2MM DMASR：`0x1000` 为 IOC 完成标志、`0x0002` 为 Idle；`0x70` 错误位掩码未置位。结合驱动报告 `16384 bytes` 与缓冲区数据保存，可确认**此次 DMA 传输完成**。这不能单独证明声学输入精度与流的长期稳定性。

## 3. 原始 PCM 文件独立复算

原文件 SHA-256：`91a6a4f66269d430add33aa63591212940d73a586845afcbdf98f61e2eb26a6e`。

| 指标 | 通道 A（低 16 位） | 通道 B（高 16 位） |
|---|---:|---:|
| 有符号 int16 最小值 | -143 | -147 |
| 有符号 int16 最大值 | 0 | 1 |
| 平均值（DC） | -81.7363 | -75.1040 |
| RMS（未去直流） | 84.2998 | 77.6327 |
| 交流分量 RMS（去均值后） | 20.6306 | 19.6525 |

- 4096 个 32-bit 字，共 16384 字节；非零 word 为 4094 个。
- 两通道相关系数（去均值后计算）约 `0.97662`，两通道相同的采样点为 113 个，通道差值 RMS 约 `7.994`。
- 数据存在明显负向直流偏置，两通道具有较高相关性；不能据此确认双麦克风隔离程度、真实声学通道独立性、SNR 或频率响应。
- 按 RTL 标称 16 kHz 解释，4096 个采样点对应 **0.256 s 标称时长**，不等于独立仪器测得的采样率。

核验命令：

```bash
python3 skill/tools/validate_capture.py \
  skill/validation/pynq_z2/rs555_audio_frame.bin --words 4096 \
  --sha256 91a6a4f66269d430add33aa63591212940d73a586845afcbdf98f61e2eb26a6e \
  --out skill/validation/audio_summary.json
```

## 4. 离线脚本测试

执行：

```bash
python3 -m unittest discover -s skill/tests -v
python3 skill/tools/overlay_audit.py \
  skill/examples/rs555_case/rs555_final.hwh \
  --contract skill/configs/rs555_contract.json \
  --bit skill/examples/rs555_case/rs555_final.bit \
  --report skill/validation/interface_audit.json
```

覆盖：HWH 正常/异常 XML、IP 缺失、地址冲突、GPIO 参数偏差、真实 16-bit DMA HWH 检查、长度门限 14/16-bit、SG 模式拒绝、PCM 有符号分拆、无效输入及真实原始数据的长度/哈希/数值复算。**离线测试不代表这些工具的所有运行分支都已在 FPGA 上执行过**。

## 5. 独立 DMA CLI 板端补测

在 PYNQ-Z2 上运行通用 `pynq_s2mm_capture.py`，补测日志见 `validation/pynq_z2/cli_test/cli_output.log`，对应的二进制输出、SHA-256、命令形式与测试说明保存在同一目录。日志记录 `DMASR=0x00001002`、16384 字节、4093 个非零 32-bit 字；已对保存数据的长度、摘要及非零字数重新核对一致。该次采集**不同于第 2 节原 Notebook 的 4094 非零字样本**，两份证据分别保留。补测验证了 CLI 独立接收，不能推论信号精度或长期稳定性。

## 6. 仍缺少的证据

- Vivado 当次完整综合/实现日志、时序、资源与功耗：不由 HWH 或 BIT 直接推导。
- 当前最新版 Vitis `main.c` 在裸机环境下的完整串口运行记录、ADXL345 ID 回读和动态诊断测试：本次 PYNQ 运行不包含它们。
- 音频模拟/数字前端质量测试：无标定输入/频谱参考/测量仪器数据，不能给出 THD、SNR、信噪比或失真合格结论。
- 不同 FPGA 题目或板卡上的实际运行：提供迁移步骤，但没有跨板卡复用实测。
- 额外的异常场景、长时 DMA 稳定性：尚未提供相应运行输出，不标记为通过。

本章节记录的作用是将“脚本本地校验”“PYNQ 板上运行”“其他整机功能”分开描述，避免用一个 PASS 结论覆盖整个项目。
