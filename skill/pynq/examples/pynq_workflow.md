# PYNQ-Z2 上的 Overlay 与 S2MM 验证流程

## 运行条件

本案例的实测环境为 PYNQ-Z2、PYNQ 2.7.0、Python 3.8.2。当前 RS555 的电机由 FPGA 按键控制，**上板进行 BIT 下载或寄存器操作前需断开电机驱动器功率电源**；不要同时启动 Vitis/JTAG 裸机程序。上传至 Jupyter 的 BIT/HWH 同名且来自预期的相同构建流程。文件名和内存地址均为 RS555 案例，迁移时必须改成新工程实际值。

## 1. 只读 HWH 元数据

```python
from pynq import Overlay
ol = Overlay('rs555_final.bit', download=False)
for name, info in sorted(ol.ip_dict.items()):
    addr = info.get('phys_addr')
    print(name, hex(addr) if addr is not None else 'NO_MMIO_ADDRESS')
```

`ps7` 缺少 `phys_addr` 为正常元数据现象。只读解析可能报告 AXI IIC 2.1 与 PYNQ 旧驱动 2.0 的版本警告，此时尚未验证该 IP 的软件功能。使用 `download=False` 不改变 PL 当前配置。

## 2. 下载前核对 DMA 参数

```python
p = ol.ip_dict['axi_dma_audio']['parameters']
width = int(p.get('C_SG_LENGTH_WIDTH', p.get('c_sg_length_width')))
assert width >= 15, '4096x32-bit needs length >= 16384 bytes'
assert 4096*4 <= (1<<width)-1
print('Length width:', width)
```

本案例曾在旧 HWH 中检测到 14，修复 Tcl 后新 HWH 为 16。该检查属于预条件，不能取代实际 DMA 到 DDR 接收。

## 3. 下载及只读 MMIO

在外部功率侧已独立隔离、无 Vitis/JTAG 并行会话的条件下：

```python
from pynq import MMIO
ol.download()
assert ol.is_loaded()

def read_status(name, offset=0):
    ip = ol.ip_dict[name]
    return MMIO(ip['phys_addr'], ip['addr_range']).read(offset)

s0 = read_status('axi_gpio_status0')
s1 = read_status('axi_gpio_status1')
s2 = read_status('axi_gpio_status2')
motor = read_status('axi_gpio_status2', 0x8)
print(hex(s0), hex(s1), hex(s2), hex(motor))
```

以上仅访问原设计中作为输入反馈的 GPIO。若不同工程的读取具有副作用，应先核对设备手册，不能机械套用。

## 4. 实测完整帧 DMA

对于 RS555 当前的 simple S2MM，示例实例名 `axi_dma_audio`，帧长 4096 word，每字低 16 位通道 A、高 16 位通道 B。推荐直接参考 `validation/pynq_z2/skill_overlay_validation.ipynb` 中执行序号 15 的原始操作及输出。该记录的一次接收结果为 `DMASR=0x1002`、16384 字节、4094 个非零字，原始二进制见 `validation/pynq_z2/rs555_audio_frame.bin`。

CLI 独立上板补测已完成；下面为 RS555 工程的执行示例，原始日志与保存的帧数据见 `validation/pynq_z2/cli_test/`：

```bash
python3 skill/tools/pynq_s2mm_capture.py \
  --bit rs555_final.bit --dma axi_dma_audio \
  --words 4096 --timeout 3 --out audio_words.bin \
  --download --ack-safe
```

CLI 先核对 DMA 元数据，后下载 PL；DMA 启动后以 DMASR 轮询 `IOC + Idle`。错误或超时会尝试对 S2MM 通道复位。无法确认复位完成时绝对不要释放可能仍被 DMA 使用的 buffer 或立即再次采集；不同 DMA/驱动版本应单独确认恢复手段。这个 3 秒为程序保护门限，不是硬件实时响应指标。

## 5. 数据结果与失败条件

```bash
python3 skill/tools/validate_capture.py audio_words.bin --words 4096
python3 skill/tools/pcm_decode.py audio_words.bin --out audio_samples.csv --rate 16000
python3 skill/tools/wav_export.py audio_words.bin --out audio.wav --rate 16000
```

PCM 解码只适用于当前 `{pcm_b, pcm_a}` 32-bit 打包、小端 DDR 读出和两个有符号 16-bit 通道。若工程无法生成正确 TLAST、buffer 长度与 TLAST 不相符、数据总线宽度改变或 DMA 驱动不同，停止套用当前接收模板并根据工程接口调整。

音频测试的主要 PASS 条件是完整帧传输、DMASR 无错误、缓存失效后原始数据长度正确；**不能使用“非零字数大于零”代替信号质量验收**。

补测日志记录 `DMASR=0x00001002`，16384 字节，4093 个非零数据字；它与原 Notebook 的 4094 个非零数据字属于不同采集轮次。
