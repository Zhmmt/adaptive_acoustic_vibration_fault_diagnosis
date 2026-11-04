# RS555 实际板级数据采集操作规程（最终优化版）

## 0. 版本确认

仅使用 `board/deploy/rs555_final.bit` 对应的最终优化硬件与实际启动所用 ELF。Windows 终端分别执行：

```bat
certutil -hashfile board\deploy\rs555_final.bit SHA256
certutil -hashfile board\deploy\rs555_vitis_app.elf SHA256
```

若 Vitis 实际下载的 ELF 来自其它路径，必须对 **那个实际文件** 而非归档 ELF 取哈希，写入测量 CSV。每次测试记录时间、供电条件、文件版本和测试项目；不得用拍摄照片推定加载的 ELF 哈希。

## 1. 连续串口日志（不需额外仪器）

工具：Vitis 2026.1，PYNQ-Z2 JTAG 运行优化版 BIT + Vitis C 程序，串口 115200/8N1；仅一个软件打开串口（关闭 Vitis 内两个 COM6 终端及其它占用程序后再使用命令行采集）。

```bat
python -m pip install pyserial
python scripts\capture_uart.py --port COM6 --duration 120 --start-live --output board\measurements\uart_run_01.txt
```

`--start-live` 仅发送一个字符 `s`，触发 `main.c` 的只读实时状态输出；程序结束尝试发送 `x` 退出实时模式，不会远程启动电机。电机必须由板载物理按钮控制。程序在每行前增加 PC 接收时间，保留原始串口字符串。记录停止、正常运行、PWM 阶跃及停止至少三个工况；采集时不要打开其它 COM6 终端。也可仅在 Vitis 终端使用 `p` 获取单次状态或 `s` 进入实时输出并保存文本。`a` 会尝试 DMA 捕获，须另外进行 DMA 长度检查后再作为完整音频帧证据。

串口应保留启动信息、ADXL345 DEVID 与配置回读、`RPM`、`Vib`、`SoundA`、`SoundB`、`DMICAlive` 等字段，以及故障/重试输出，不得仅保留成功行。若出现 `Access denied`，关闭另一串口终端而不是修改 `main.c`。

## 2. 示波器 PWM 周期与占空比

现有实验照片可确认现场使用过示波器，但照片上探头测量点不够明确，不能把波形直接认作 PWM 或测速参考。必须标注本次探头接入端口。示波器 CH1 接 **3.3 V PWM 逻辑信号**（实际工程 JB1/W14），地夹仅连接与 PYNQ 共地的安全低压地；示波器地线可能接保护地，**禁止直接夹在电机功率引脚或不明确的高电位节点**。电机上电前先核对电平、供电与接线。选择 ×10 探头和相应示波器倍率。

在电机被安全停转、正常运转等工况测 CH1 Frequency、Period、Positive Width，至少选择三个占空比，稳定后各记录 3 次。对于 25 kHz 目标，理论周期是 40 μs；50% 时理想高电平 20 μs。数值必须来自示波器测量值，写到 `pwm_scope.csv`，并附同时刻串口或 LCD PWM 读数及原始仪器截图。

## 3. 无独立转速表时的 RPM 参考

示波器 CH2（或单独测量）连接 HC-020K 的 **已确认不超过 3.3 V 的输出**（工程接入 JB7/V16）；如传感器输出 5 V，先使用正确电平转换，绝对不能直接接 FPGA 输入。测稳定转速的脉冲频率 `f_pulse`。先由实物码盘和 RTL 同步边沿确认一转产生 `PPR=20` 个有效计数脉冲，再计算：

`RPM_ref = 60 × f_pulse / PPR`，在 PPR=20 时即 `RPM_ref = 3 × f_pulse`。

从相同工况串口日志读取 `RPM`（它的测量门窗约 1 s，必须在转速稳定后比较），保存同一时间段的示波器截图、UART 日志与表 `tach_reference.csv`。误差为 `abs(RPM_uart-RPM_ref)`；相对误差只对参考 RPM>0 计算。示波器对同一个光电脉冲信号的频率计算，可以验证 FPGA 测频/换算，但它并非与光电脉冲无关的独立机械转速表，报告应说明这一参考方法的边界。

## 4. 传感器 / LCD / 音频

按原 Vitis 功能安全运行，分别记录停止、正常运行及安全的工况变化下 `ADXL345 DEVID=0xE5` / XYZ / Vib / SoundA / SoundB / DMICAlive / LCD 显示，并将原始终端文本与同时刻照片链接至 `sensors_observed.csv`。不要把“声音数值变化”写成“故障诊断准确率”；如评估诊断准确率，需要具有独立工况标签的真实数据集。

## 5. DMA 的必须核查项

最终主工程 HWH 记录 DMA `C_SG_LENGTH_WIDTH=14`，单次请求 `4096×4=16384` 字节需核查长度限制。完整 16384 字节传输不得仅根据 Vitis 的 `Capturing...` 提示或 PYNQ Skill 的 DMA16 Notebook 推断为成功。使用独立 DMA16 验证版本时，应记录其独立 BIT/HWH 哈希及真实 `DMA status`、数据文件，并与当前正式主工程分开标记。如果本版本无法完成完整传输，在报告中列明为已知边界，不写“4096 帧成功”。

## 6. 归档规则

每个测量条件至少保存：`原始 UART TXT + 仪器截图 + 填写的 CSV + BIT/ELF SHA256 + 操作日期时间`。不填写真实数据的空白模板不构成测量结果。命名和文档不含身份、学校或报名资料；原始仪器图片与日志不进行伪造或消除失败信息。
