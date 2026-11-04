# PYNQ-Z2 DMA CLI 独立上板测试

## 1. 测试环境
- 开发板：PYNQ-Z2
- 软件环境：PYNQ Linux
- FPGA 工程：RS555 Overlay
- DMA 实例：axi_dma_audio
- 测试工具：pynq_s2mm_capture.py

## 2. 测试参数
- DMA 方向：S2MM
- 数据字数：4096
- 每个数据字宽度：32 bit
- 接收数据量：16384 bytes
- 超时时间：3 s

## 3. 实测结果
- DMA Length Width：16 bit
- 最大 DMA 传输长度：65535 bytes
- DMASR：0x00001002
- 实际传输：16384 bytes
- 非零数据字：4093
- 输出文件：audio_words.bin
- 文件大小：16384 bytes

## 4. 验证结论
通用 DMA CLI 已在 PYNQ-Z2 开发板上独立运行，
完成一次 16384 字节 S2MM 数据传输。

本次验证证明了 CLI 基本数据接收功能可用，
不涉及音频保真度、识别准确率或跨板卡性能验证。

## 5. 证据对应关系
- `cli_output.log` 是本次重新运行 CLI 保存的日志；本次非零数据字为 4093。
- `audio_words.bin` 与 `file_sha256.txt` 对应此次日志记录，不是原 Notebook 的音频帧。
- 原 Notebook 中非零数据字 4094 为另一轮采集，不能与本次日志混写。
- 日志保留 AXI IIC 驱动版本提示；本次未测试 AXI IIC 读写。
