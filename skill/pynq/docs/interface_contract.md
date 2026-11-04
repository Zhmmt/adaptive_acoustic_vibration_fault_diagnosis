# RS555 实例接口契约与通用迁移原则

## 1. 契约来源

以下信息核对自交付工程的 `vivado/build_overlay.tcl`、`rtl/rs555_system_core.v`、`rtl/motor_pwm.v`、`deploy/rs555_final.hwh` 以及额外提交的新版 `main.c`。`configs/rs555_contract.json` 记录了 HWH 中的实例、地址、IP 版本和参数。地址属于本次硬件导出，不具有跨项目固定性。

| 外设实例 | 基地址（案例 HWH） | 用途 |
|---|---|---|
| `axi_dma_audio` | `0x40400000` | AXI DMA simple S2MM，32-bit packed stereo |
| `axi_gpio_ctrl` | `0x41200000` | 软件急停及 LCD 故障覆盖状态，16-bit 输出 |
| `axi_gpio_status0` | `0x41210000` | `{rpm[15:0], vibration[15:0]}` |
| `axi_gpio_status1` | `0x41220000` | `{sound_a[15:0], sound_b[15:0]}` |
| `axi_gpio_status2` | `0x41230000` | channel 1 标志/ID/PCM 计数；channel 2 电机运行状态 |
| `axi_gpio_adxl_sw` | `0x41240000` | Vitis 从 IIC 读数后供给 PL 的 ADXL 值 |
| `axi_iic_adxl` | `0x41600000` | AXI IIC 控制器，ADXL345 7-bit 地址 `0x53` |

实例名以 HWH 为准，不能把 `axi_gpio_0` 的排序当作约束。裸机端可用 `xparameters.h` 中对应实例地址宏，避免按设备序号误选控制口。PYNQ 端使用 `Overlay.ip_dict`、`register_map` 对照实例名。

## 2. AXI GPIO 数据约定

- status0 channel 1（DATA + `0x0`）：`[31:16] RPM`、`[15:0] 振动变化量`。
- status1 channel 1（DATA + `0x0`）：`[31:16] 声音 A`、`[15:0] 声音 B`。
- status2 channel 1（DATA + `0x0`）：`[31:16] PCM_count_low16`、`[15:8] ADXL_DEVID`、`[7:0] flags`；flags bit0 ADXL 就绪，bit1 码盘曾产生脉冲，bit2 电机开启，bit3 LCD 故障显示，bit4 LCD 已完成帧，bit5 数字麦克风有过有效输出。
- status2 channel 2（DATA + `0x8`）：`[7:0] PWM 百分比`、`[8] 运行状态`、`[9] 软件 ESTOP`、`[10] LCD 实际故障位`；这是只读反馈，不是电机控制寄存器。
- ctrl channel 1（DATA + `0x0`）：`[9] 软件 ESTOP`、`[10] fault_override_valid`、`[11] fault_override`；其他位保留。写之前明确控制器方向寄存器，禁止把旧版 duty/enable 写入此处。
- adxl_sw channel 1（DATA + `0x0`）：`[15:0] 振动变化量`、`[23:16] DEVID`、`[24] ready`，由 Vitis 写入；缺失传感器数据时 `ready=0`，不得等同零振动有效值。

AXI GPIO 常见相对偏移：channel1 DATA `0x0`、TRI `0x4`、channel2 DATA `0x8`、TRI `0xC`。实际实例的双通道配置先以 HWH 参数 `C_IS_DUAL` 和文档为依据。

## 3. AXI IIC 与异常状态

本工程中 ADXL345 通过 AXI IIC 地址 `0x53` 访问，读设备 ID 期望 `0xE5`。新版 C 先写 IIC 寄存器指针，随后 REPEATED_START 读取；配置依次包含 `POWER_CTL=0x00`、`DATA_FORMAT=0x08`、`BW_RATE=0x0A`、`POWER_CTL=0x08`，再回读关键配置寄存器。传感器未连接、ID 错误、读数失败均应进入 `SENSOR_ERROR`，而不是作为正常值参与基线训练。

C 程序的 `vibration_state` 数值含义：0 未形成有效判断，1 NORMAL，2 ABNORMAL，3 SENSOR_ERROR。进入 NORMAL 需要有效的声/振动参考以及 **相同 PWM 档位** 的转速参考。新 C 源中转速持续下降阈值 15%、恢复阈值 8%，判断须经过相应计数确认；这是一组**当前代码阈值**，不是基于本次提交数据得到的精确误报率或漏报率。

## 4. DMA 帧与缓存契约

工程中 AXI DMA 为 simple S2MM，数据总线 32 bit；`axis_stereo_frame.v` 在一帧末尾发 TLAST，并提供 `TKEEP=4'b1111`。案例参数为一帧 4096 个 32-bit word、16 kHz 采样率（约 256 ms）。低 16 位为有符号通道 A，高 16 位为有符号通道 B。`pcm_decode.py` 以 little-endian 解释接收到的内存字节。

Vitis C 使用 64 字节对齐静态缓冲区，DMA 前清理/失效相应地址的 CPU 缓存，传输完成后再次失效缓存，并检测 RX error、超时、复位状态。PYNQ Python 示例以 `allocate()` 得到可供 DMA 使用的缓冲区，等待传输完成，随后执行接收后 invalidate 并释放。PYNQ 各版本内部是否自动执行缓存同步，应以实际驱动实现为准；不要把缓存正确性从软件运行推断为板端正确性。

若流无法产生完整 TLAST、字数与 DMA buffer 不匹配，PYNQ `wait()` 可能无法返回；本模板不是带看门狗的生产级 DMA 服务。

## 5. 更换板卡/题目

保留审计/解码工具，替换如下项目专用契约：

1. 由新 Vivado 工程导出对应 `.hwh` 和 `.bit`，确保构建流程与目标板卡一致。
2. 根据新 `.hwh` 修改 JSON 的 `device`、`instances`、地址和相关 IP 参数，绝不能盲用以上地址。
3. 核对新业务 FPGA 的 AXI GPIO 输出/输入位定义，不允许以旧工程的软件寄存器假设操作电机或执行机构。
4. 根据实际 AXI-Stream 方向、TDATA 位宽、TLAST 帧界和缓存策略修改板端传输模板。
5. 如果不再是双路有符号 16 位打包流，则修改或舍弃 PCM 解码，不得把解析成功当成协议相同。
