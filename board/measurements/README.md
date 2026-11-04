# 真实板级数据记录（空白模板）

保留原始串口和仪器输出，不以示例值代替实测。按 `measurement_protocol.md` 完成采集，将结果填写到 CSV；若某项无独立仪器或没有明确输出，标为“未测”，不写通过。任何记录不得包含姓名、学校、学号或队伍身份。

- `uart_log_*.txt`：实时串口原始输出，UTF-8、逐行时间戳（运行后生成）
- `pwm_scope.csv`：PWM 理论/实测时序
- `tach_reference.csv`：光电脉冲对照 RPM
- `sensors_observed.csv`：传感器及 LCD/UART 观察记录
- `dma_capture.csv`：DMA 接收长度、状态及样本核验

## 已新增的实测数据（第 3 次整理）

- `tach_reference.csv`：7 组 PWM 工况脉冲频率与 FPGA RPM 对照；误差按 `PPR=20` 计算；与原始图像一同提供，非独立机械标定。
- `tach_reference_original.png`：未经编辑的用户原始数据截图。
- `tach_reference_analysis.md`：公式、7 组换算结果和证据边界。
- `uart_run_01_with_adxl_error.txt`：第一次真实串口采集，中途曾出现 ADXL345 读失败；保留完整原文。
- `uart_run_02_sensor_ok.txt`：第二次真实串口采集，记录停止、启动、调速及再停止；235 个状态行 Sensor=OK。
- 已有的 `pwm_scope.csv` 仍是空白模板：这些转速频率读数不可替代 PWM 载波频率/占空比的独立仪器量测。
