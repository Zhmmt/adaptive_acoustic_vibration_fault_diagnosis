# 故障与纠错记录

| 触发条件 | 复现证据 | 处理方法 | 迁移价值 |
| --- | --- | --- | --- |
| FIR 流水线仿真 `VALID_FAIL idx=0 got=1 expected=0` | DUT 中仍有旧版 `sum[47:0]` | 使用 `get_files -all *fir31.v` 找出重复源；仅保留一个综合版本，重新编译 | 消除源码路径混淆 |
| 工程完成布局布线但时序失败 | 最初 WNS -39.029 ns，31 级 FIR 路径 | 注册乘积、平衡加法树，重跑 HDL 与 routed STA | 计算深度优化 |
| LCD 最差路径与显示刷新关联 | `snap_rpm` 至 `pix_reg` | 每帧进行 BCD 预计算，保留显示格式检查 | 切断像素路径中的常量除法 |
| 后续最差路径转移到测速 | `tach0/rpm1 → rpm_reg` | 验证当前 20 PPR 常量等式后特化 | 参数化与专用优化并存 |
| 把 Windows `cd /d` 粘贴进 Vivado Tcl | Tcl `wrong # args` | Tcl 使用 `cd D:/...`；批处理脚本在 CMD 执行 | 避免混用工具终端 |
| Vitis 串口 `COM6 Access denied` | 端口被第二终端占用 | 关闭重复 COM 会话，确认 115200 8N1 后继续调试 | 排除工具占用而非硬件故障 |
| 生成 BIT 后仍无法确信 ELF 匹配 | 旧/新 HWH 可能不同 | 检查地址、IP 参数及板级功能；保留构建哈希 | 防止版本错配 |
