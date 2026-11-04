# 独立 DMA CLI 板端验证证据

此目录记录 PYNQ-Z2 上运行 `pynq_s2mm_capture.py` 的复测。`cli_output.log` 为保存的程序输出，`audio_words.bin` 为该次运行生成的数据；`file_sha256.txt` 记录当前二进制文件的 SHA-256，`test_notes.md` 记载测试设置和结果。

`command.txt` 保存最初执行的命令形式（输出位于工作目录）；为将数据直接写入此证据目录，复测运行时将 `--out` 调整为 `validation/pynq_z2/cli_test/audio_words.bin`，详见日志中的 `Saved` 行。日志没有记录精确执行命令行，不能单独用日志证明所有启动参数。

复测记录：`DMASR=0x00001002`，16384 字节，4093 个非零 32-bit 字。原始 Notebook 的 4094 为另一轮测试。完成状态表明该帧 DMA 接收完成，不说明音频保真度或整机诊断性能。
