# 可复用工程技能包

## 作品名称与定位

本 Skill 随作品《自适应声振融合故障诊断系统》发布。RS555 是内部 FPGA 工程标识；以下工具均以工程接口与验证任务为复用对象，不固化电机型号、诊断阈值或现场接线。

## Skill 总览

| 技能 | 适用场景 | 入口 | 已验证效果 | 失效条件 |
|---|---|---|---|---|
| FPGA 时序审计 | Vivado 路由后时序报告批量分析 | `timing/README.md`、`tools/timing_audit.py` | 读取 V6 与最终实现报告并发现不满足约束的基线 | 缺少 routed timing report；未约束路径不能由 WNS 覆盖 |
| AXI/HWH 契约校验 | Zynq/AXI IP 地址与参数一致性 | `interface/README.md`、`tools/hwh_contract.py` | 主工程地址、关键参数检查 | IP 未列入检查规则或 HWH 非同次构建 |
| 仿真与证据验收 | RTL testbench 与回归日志 | `verification/README.md`、`tools/simulation_gate.py` | 原工程若干编译/历史仿真验收；独立 runtime 证据另存 | 仅编译不能证明全部功能正确 |
| 通用 PYNQ Overlay/DMA | 其他题目的 Overlay、AXI-Lite、simple S2MM 与数据验证 | `pynq/README.md`、`pynq/tools/` | PYNQ-Z2 实例的 16,384 B DMA 实测；独立 GPIO 工程离线契约审计 | SG、MM2S、无 TLAST、未知数据格式需适配 |

## 跨题目应用场景

- **风机及水泵**：可复用 AXI 地址、DMA 容量和数据完整性检查，传感器量程及诊断算法需替换。
- **输送机与旋转机构**：复用 GPIO/AXI 寄存器和时序约束审计，不复用 RS555 的控制位或安全默认值。
- **多通道声学采集**：复用 S2MM 采集、缓存同步及 PCM 格式核验；须重新确认通道打包和 TLAST。
- **通用 GPIO 教学工程**：已有另一套 AXI GPIO 的 HWH 静态 PASS 及故意错误 FAIL 记录；没有跨板卡实测。
- **其他 AMD FPGA 项目**：可用 Vivado 报告解析和版本追溯脚本，不要求与 RS555 具体业务相同。

操作与边界详见 `pynq/docs/reuse_scenarios.md`、`pynq/docs/reuse_checklist.md`。

## 快速核验

在工程根目录运行：

```bash
python -m unittest discover -s skill/tests -v
cd skill/pynq
python -m unittest discover -s tests -v
python tools/overlay_audit.py examples/rs555_case/rs555_final.hwh --contract configs/rs555_contract.json --bit examples/rs555_case/rs555_final.bit
python tools/validate_capture.py validation/pynq_z2/rs555_audio_frame.bin --words 4096
```

通用工具可迁移，验证结论不迁移：将其用于其他项目需替换 BIT/HWH、IP 契约、数据格式并重新运行测试。

## 技能形成与测试分级

原始工程存在 100 MHz setup 时序不收敛、DMA 长度字段 14 bit 不足 16,384 B 帧、HWH 接口契约及外设驱动警告等问题。通用方法提炼为：**复核源文件版本 → 读取报告和接口契约 → 预检 DMA 和缓存 → 运行真实板端操作 → 保留独立文件校验和异常记录**。已保存的 PYNQ 案例与本项目最终构建的 BIT 哈希不同，不能交叉当作同一次实验的证据。

本目录为比赛指南 3.3.5.2 所要求的可复用经验。真实交互协作记录见 `../report/model_collaboration_record.md`；主要输出采用工程技术文档格式，不将未经证实的诊断准确率、跨板卡运行或仿真结果写为已通过。
