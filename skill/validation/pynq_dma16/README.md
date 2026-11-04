# 独立 PYNQ DMA16 验证材料

本目录存放从 PYNQ/Jupyter 原始运行环境导出的 Notebook 与 PCM 二进制数据。它们属于独立的 DMA16 示例验证，不等同于 `board/deploy` 中的正式主工程 DMA14 BIT/HWH（若后续版主工程升级，应以该版最新硬件文件为准）。

本包未提供与此 Notebook 可独立识别的成套 DMA16 BIT/HWH，故运行笔记本前须确保加载的文件来自实际 DMA16 构建；禁止以此 Notebook 的成功输出声称 DMA14 已完成 16384 字节单次传输。Notebook 可能保留 AXI IIC 驱动版本提示，应如实记录。
