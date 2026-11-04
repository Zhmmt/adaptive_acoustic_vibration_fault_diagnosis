# 通用 PYNQ Overlay 与 DMA 数据验证 Skill


本目录是从声振故障诊断工程开发中整理的可复用工具，服务于三类常见任务：核对 Vivado 导出的 AXI 接口信息、在 PYNQ Linux 上检查和接收 simple S2MM 数据、对接收到的二进制数据进行长度与格式核验。**工具面向接口而非故障诊断算法**；RS555 仅用于提供可核查的实测案例。

## 1. 适用范围和使用前提

| 工具 | 适用于 | 使用前必须确认 |
|---|---|---|
| `make_contract.py` / `overlay_audit.py` | 有 HWH 的 AXI 工程；普通电脑可离线运行 | IP 名称、地址范围和参数由目标工程决定；自动生成的契约须人工核对 |
| `pynq_probe.py` | 可运行相应 PYNQ 软件环境的板卡 | BIT/HWH 与目标硬件对应；仅解析元数据不代表 FPGA 已配置 |
| `pynq_s2mm_capture.py` | PYNQ 平台的 AXI DMA simple S2MM、固定长度 AXI-Stream 接收 | 已确认 DMA IP、长度字段、帧结束 TLAST、缓冲区与复位行为 |
| `validate_capture.py` / `pcm_decode.py` / `wav_export.py` | 字节长度、摘要核验；指定的双声道 PCM 打包 | 其他采样位宽、通道顺序、大小端或数据格式须先修改参数／工具 |

不适合直接套用的情形包括：AXI DMA Scatter-Gather、MM2S 发送链路、无 TLAST 的不完整帧、未经适配的板卡 BIT/HWH、与此案例不同的数据封装。对于其他工程，可只使用接口审计部分，不必使用 DMA/PCM 工具。

## 2. 目录与证据

```text
skill/
├── README.md
├── tools/                 # 7 个通用工具脚本
├── tests/                 # 离线测试
├── configs/               # RS555 案例契约与来源索引
├── docs/                  # 接口约定、验证、排障、复用检查清单
├── examples/              # 离线使用示例、PYNQ 流程与 RS555 案例
├── validation/
│   ├── pynq_z2/
│   │   ├── skill_overlay_validation.ipynb  # 原始 Notebook 上板记录
│   │   ├── rs555_audio_frame.bin           # 原 Notebook 采集数据
│   │   └── cli_test/                       # 独立 CLI 补测的日志和数据
│   ├── interface_audit.json
│   └── offline_test_log.txt
└── report/                # 供设计报告引用的 Skill 摘要
```

**如何判断复用性**：新工程更换 HWH/BIT、IP 实例名及寄存器契约后，应能继续使用通用审计流程；如需 DMA，须按实际硬件更改实例名、帧长与数据协议。本包已验证 RS555 工程及通用 CLI 在同一 PYNQ-Z2 板上的使用；**尚未提供另一个非 RS555 工程或第二块板卡的运行记录**，不把参数化能力写成跨工程实测结论。

## 3. 无板卡快速检查（推荐从这里开始）

在**包含 `skill/` 目录的项目根目录**执行。离线脚本用 Python 3.9+ 标准库即可，板端 PYNQ 环境独立配置。

```bash
python3 -m unittest discover -s skill/tests -v
python3 skill/tools/overlay_audit.py \
  skill/examples/rs555_case/rs555_final.hwh \
  --contract skill/configs/rs555_contract.json \
  --bit skill/examples/rs555_case/rs555_final.bit \
  --report interface_audit_check.json
python3 skill/tools/validate_capture.py \
  skill/validation/pynq_z2/rs555_audio_frame.bin --words 4096
```

这里 `overlay_audit.py` 依据**已有、经审阅的契约**检查 HWH；不能通过“从同一份 HWH 自动生成契约后再审计”单独证明硬件设计正确。针对不同项目，先用下面的命令生成初稿，再对照 Vivado 地址分配和 IP 设置进行人工审阅：

```bash
python3 skill/tools/make_contract.py other_design.hwh --out other_contract.json
python3 skill/tools/overlay_audit.py other_design.hwh \
  --contract other_contract.json --report other_audit.json
```

更换工程的检查顺序见 [`docs/reuse_checklist.md`](docs/reuse_checklist.md)，契约字段含义见 [`docs/interface_contract.md`](docs/interface_contract.md)。

## 4. PYNQ 上的独立 DMA 接收

本节命令使用 **RS555 的 BIT/HWH 和 DMA 实例名**；在其他工程上须替换，不是通用默认配置。

准备：开发板为 PYNQ-Z2，系统运行 PYNQ Linux；将同一工程对应的 `rs555_final.bit`、`rs555_final.hwh` 与 `pynq_s2mm_capture.py` 放在同一目录。操作前独立断开电机驱动器功率电源，停止并行占用 PL/DMA 的进程与 JTAG 会话，确认设备安全状态。`--ack-safe` 只是人工安全确认参数，**不执行断电**。

```bash
python3 pynq_s2mm_capture.py \
  --bit rs555_final.bit \
  --dma axi_dma_audio \
  --words 4096 \
  --timeout 3 \
  --out audio_words.bin \
  --download \
  --ack-safe
```

此命令实际重新配置 PL 并接收 4096 个 32-bit 数据字（共 16384 字节）。`--timeout 3` 是等待超时设置，不能当作性能或处理延迟指标。接收之后可使用 `validate_capture.py` 检查文件长度、摘要及数据统计；声振案例还可按实际格式用 `pcm_decode.py`、`wav_export.py` 输出 CSV/WAV。完整步骤与恢复注意事项见 [`examples/pynq_workflow.md`](examples/pynq_workflow.md)。

如 DMA 超时或返回错误状态，不应强行连续重试。工具尝试接收侧复位；未确认复位完成时，先使硬件处于安全状态，再检查 TLAST、时钟、长度字段、DMA 模式及缓存/驱动状态。**不能仅因产生了非零数据就认定音频质量合格。**

## 5. 已验证效果

| 项目 | 证据 | 结果与结论 |
|---|---|---|
| HWH / 接口契约离线审计 | `validation/interface_audit.json`、`tests/` | RS555 新版 HWH 的 7 个关键 IP 检查通过；这是静态契约检查 |
| 原始 PYNQ Notebook 上板 | `validation/pynq_z2/skill_overlay_validation.ipynb` | Overlay 加载、MMIO 状态读取、simple S2MM 接收；`DMASR=0x1002`、16384 B、4094 个非零字 |
| **独立 DMA CLI 上板补测** | `validation/pynq_z2/cli_test/` | `cli_output.log` 记录 `DMASR=0x00001002`、16384 B、**4093** 个非零字；对应数据和 SHA-256 随包保存 |
| PCM 数据格式验证 | `validation/pynq_z2/rs555_audio_frame.bin`、`audio_summary.json` | 可按案例的 `{B,A}` 两路 signed 16-bit 数据格式分拆；不代表音频质量校准 |

**两次采集必须分开引用**：原 Notebook 为 4094 个非零字；新上传的 CLI 日志与数据为 4093 个非零字。补测数据的 SHA-256 见 `validation/pynq_z2/cli_test/file_sha256.txt`；详见 [`docs/validation.md`](docs/validation.md)。CLI 运行日志还记录了 AXI IIC 驱动版本告警，该告警未阻断本次 DMA 接收，但不代表 AXI IIC 功能已经验证。

已验证的是特定板卡上的接口解析、寄存器访问以及一帧 DMA 搬运。没有相应证据的项目——如跨板卡实测、另一工程的完整复用、音频频率响应／保真度、整机诊断准确率、Vitis 裸机完整闭环和综合资源时序——不纳入本 Skill 的成功结论。

## 6. 由失败记录整理出的排查方法

- **DMA 帧长临界问题**：旧 HWH 的 DMA 长度字段为 14 bit，最大可表达 16383 B；本工程一帧需要 4096×4=16384 B，差 1 字节。修改并核对新版 16-bit 参数后，再通过板上完整帧接收确认。参见 `docs/troubleshooting.md` 和两版 HWH。
- **HWH 元数据误用**：处理器 `ps7` 条目没有普通 AXI 外设那样的 `phys_addr`，不应将其作为 MMIO 外设读取。外设地址需依据 HWH 和审阅后的契约匹配，而非硬编码列表顺序。
- **PYNQ 启动及驱动警告**：原记录包含 ext4 启动故障，以及 AXI IIC IP 版本警告。它们是发生过的观察；排障应先确认实际症状，不应将所有启动异常归为同一原因。
- **接收完成与信号质量区别**：DMA IOC/Idle 置位和缓冲区长度正确只确认搬运完成。数据幅度、通道串扰、故障诊断效果需要独立测试。

相关触发条件、定位步骤见 [`docs/troubleshooting.md`](docs/troubleshooting.md)，其它寄存器及状态位边界见 [`docs/status_machine_pattern.md`](docs/status_machine_pattern.md)。

## 7. 交付与许可

Skill 可作为参赛项目仓库根目录中的 `skill/` 提交，但**不替代**完整工程、上板工程与实测、综合/实现报告、设计报告和真实大模型协作记录。通用 PYNQ Skill 是否额外加分由赛方评定，提交时可直接援引第 1、3、5、6 节的复用方法与证据。

本包新增工具与文档的许可见 `license.txt`；示例中引用的 RTL、C、BIT/HWH 及第三方 IP 不因此改变原有权利归属。


## 非 RS555 工程复用验证（AXI GPIO）

使用独立 Vivado AXI GPIO 工程导出的 `gpio_demo.hwh`，在不修改通用工具源码的情况下运行 `make_contract.py` 和 `overlay_audit.py`。生成并审核原始接口契约后，静态审计结果为 PASS；将测试契约的 `C_GPIO_WIDTH` 从 8 故意改为 16，审计结果为 FAIL，指出实际值 8 与期望值 16 不符。两项结果及原始 HWH 均保存在 `validation/gpio_demo/`，复现命令见该目录下的 README。

此案例证明工具可应用于另一种 AXI 外设工程，并能发现已知参数不匹配；验证仅针对 HWH 静态元数据，不代表新 GPIO 工程已上板运行或完成跨板卡验证。
