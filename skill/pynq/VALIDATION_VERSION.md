# DMA16 样例与主工程的区别

PYNQ 已执行的 Notebook 和 `validation/pynq_z2/rs555_audio_frame.bin` 属于独立 PYNQ Overlay 示例硬件：

- 示例 BIT：`examples/rs555_case/rs555_final.bit`，SHA-256 `6489162f0de50b9518736136477c05d83dde119c786019b5e233bf53d377230b`
- 最新参赛主 BIT：`../../board/deploy/rs555_final.bit`，SHA-256 `09f07194424552bd127429e656af091e8701d18a308bb8f40f704845ee98f242`

**不是同一个 BIT**。现有 Notebook 不能作为新主 BIT 的完成记录。工具和接口检查方法可以迁移，硬件实测结论不能迁移；新主 BIT 的 DMA 接收与 Vitis 整机回归需补测并归档。
