# 优化版仿真证据

`testbench/` 收录最终 RTL 对应的五项综合回归仿真；`compile_logs/` 是来源压缩包中保留的真实编译输出，不应当作运行时 PASS 标记。用户此前在 Windows Vivado 命令提示符中运行 `scripts/run_hdl_tests.bat`，控制台出现 `ALL_SIM_TESTS_PASS`。如需独立检查每一项实际仿真结束标记，请在 Vivado 2026.1 Command Prompt 重新执行脚本，保存新的 `reports/simulation/*_sim.log`。

建议命令：

```bat
call "D:\AMD\2026.1\Vivado\settings64.bat"
cd /d <this-project-root>
scripts\run_hdl_tests.bat
```

运行脚本直接以五个 PASS 标记验收 XSim 完整日志，无通过标记或有执行错误则退出失败。
