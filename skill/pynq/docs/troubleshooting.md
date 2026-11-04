# 工程失效案例与定位顺序

本页将**已实际观察到的现象**与**从源码确认但未在当前上板测试中复现的潜在风险**区分记录。各项方法适用于具有同类接口的工程，移植时先核对目标 IP/寄存器规格。

## 一、已经出现并定位的问题

### 1. PYNQ Linux 启动时无法访问 Jupyter

- **实际现象**：Windows 网卡直连地址 `192.168.2.1/24`、链路 100 Mbps，但 `192.168.2.99` ping 不通、ARP 表无该地址。
- **串口依据**：Linux 日志有 `JBD2: journal transaction ... is corrupt`、`EXT4-fs (mmcblk0p2): error loading journal`、`Kernel panic - not syncing: VFS: Unable to mount root fs`。
- **判定**：不是 Jupyter 端口的首要问题；本次启动在挂载 Linux 根文件系统之前失败。
- **定位办法**：保持 SD 模式，从 PROG/UART 115200 读取启动日志；先确认根分区挂载及 Linux 登录成功，再检查 `ip -4 addr show eth0`、IP、Jupyter 端口。对需保留数据的存储卡先备份再修复；重新写入镜像会清除旧数据。
- **记录的恢复结果**：后续能够访问 Jupyter、运行 PYNQ 2.7.0 并完成板端 DMA 测试。没有存储卡健康度及故障成因的数据，不能断言是哪一次断电造成的损坏。

### 2. HWH 元数据遍历报 `KeyError: 'phys_addr'`

- **实际现象**：使用 `info['phys_addr']` 遍历 `ol.ip_dict`，在包含 `ps7` 的条目处发生 KeyError。
- **原因及修正**：`ps7` 不是以普通 AXI-Lite 外设方式映射的 IP；改用 `info.get('phys_addr')`，缺失则打印 `NO_MMIO_ADDRESS`。修正后成功列出 7 个关键 AXI 外设。
- **边界**：不可以通过为缺失项虚构 `0x0` 作为 MMIO 地址而继续访问。

### 3. 4096×32-bit DMA 帧比 14-bit 长度上限多 1 字节

- **实际现象**：旧 HWH 的 `C_SG_LENGTH_WIDTH=14`、最大长度 `(1<<14)-1=16383`，实际帧为 `4096*4=16384`。板端脚本输出 `Frame fits DMA: False`。
- **修复位置**：`vivado/build_overlay.tcl` 中的 `axi_dma_audio` 配置加入 `CONFIG.c_sg_length_width {16}`；重新综合/生成匹配的 BIT/HWH，上传到 Jupyter。
- **已确认效果**：新 HWH 显示 16、驱动 `buffer_max_size=65535`、完成一次 16384 B S2MM 接收，`DMASR=0x1002`。
- **可迁移规则**：在任何 DMA 分配缓冲区或启动传输之前，先验证每帧字节数 `<= (1<<C_SG_LENGTH_WIDTH)-1`。此规则不保证正确的 TLAST 或 AXI Stream 数据行为。

### 4. PYNQ 对 AXI IIC 2.1 版本告警

- **实际现象**：PYNQ 2.7.0 提示 `axi_iic:2.1` 与识别到的 `axi_iic:2.0` 驱动版本不一致。
- **处理**：该警告没有阻止本次 HWH 解析、DMA 配置与 S2MM 接收；IIC 的驱动读写兼容性没有得到实测确认。不得仅为消除告警就默认 `ignore_version=True` 等于验证通过。
- **迁移条件**：需要使用 AXI IIC 时必须单独验证目标芯片地址、ACK、读回内容及异常处理。

### 5. PYNQ Notebook 找不到 BIT 文件

- **实际现象**：`Overlay('rs555_dma16.bit')` 报 `OSError: Bitstream file ... does not exist`，而工作目录仅存在 `rs555_final.bit`。
- **修正**：保持同名 BIT/HWH 放在 Notebook 工作目录，或使用完整真实路径。Tcl 修改不等于开发板文件已更新；必须重新构建并上传新工件。
- **验收依据**：实际文件存在、HWH 的 DMA 位宽为 16，随后执行下载与 MMIO/DMA 验证。

## 二、源码支持的风险条件（并非本次新实测故障）

| 风险 | 源码依据 | 排查与停止条件 |
|---|---|---|
| Vitis `xparameters.h` 地址宏与新 XSA 不匹配 | 新版 `latest_main.c` 对 AXI CTRL/STATUS/DMA/IIC 地址宏设编译期保护 | 对照新 XSA/HWH 确认实例与地址；不一致时停止控制寄存器操作 |
| 无 ADXL345 仍被判断为正常 | `sensor_mark_error()` 将 ready 置 0、进入 SENSOR_ERROR | 不运行新版 Vitis 程序时，ADXL SW GPIO 不会自动得到有效数据；不可把 0 当成真实零振动 |
| 旧 Python 电机位定义被误用 | 现版 `rs555_system_core.v` 从 BTN 控制电机，GPIO bit9/10/11 用于急停/显示 | 禁用旧 `set_motor` 软件写法；必须具备独立断电；未核实寄存器方向时不得写 CTRL |
| DMA 缺少 TLAST、AXI 错误或驱动阻塞 | `axis_stereo_frame.v` 的 TLAST 在每 4096 次有效握手帧末出现；`main.c` 有 DMA 错误掩码和复位逻辑 | 核对帧长/TDATA/TKEEP/TLAST/时钟复位；接收错误时停止重试并确认通道停止，不能无条件释放缓存 |
| 音频通道解释错误 | `axis_stereo_frame.v` 使用 `{pcm_b,pcm_a}`，DDR 中每字低 16 位 A、高 16 位 B | 黄金样本校验符号扩展；字节序或打包不同则重新定义解析契约 |
| 缺少训练数据输出 NORMAL | 最新 C 源要求同 PWM 转速基线及声/振动参考、稳定窗口 | 未训练或传感器异常应保持 UNKNOWN/SENSOR_ERROR，不做正常性能承诺 |

## 三、保留的排障证据

旧版/新版 HWH、构建 Tcl、RTL、Vitis C、原始 PYNQ Notebook 和 DMA 捕获帧均位于本包，索引及校验值见 `configs/source_evidence.json`。每一个“通过”必须能够对应到明确的输入、操作和输出；未运行的条件性建议不记为成功案例。
