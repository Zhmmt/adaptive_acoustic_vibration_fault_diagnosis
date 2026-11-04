# 离线复现：接口契约与原始数据

适用于普通电脑上的 Python 3.9+ 环境，运行步骤不需要 Vivado、Vitis、PYNQ 或 FPGA 板卡。

在包含 `skill/` 的工程根目录依次运行：

```bash
python3 -m unittest discover -s skill/tests -v
python3 skill/tools/overlay_audit.py \
    skill/examples/rs555_case/rs555_final.hwh \
    --contract skill/configs/rs555_contract.json \
    --bit skill/examples/rs555_case/rs555_final.bit \
    --report skill/validation/interface_audit.json
python3 skill/tools/validate_capture.py \
    skill/validation/pynq_z2/rs555_audio_frame.bin \
    --words 4096 \
    --sha256 91a6a4f66269d430add33aa63591212940d73a586845afcbdf98f61e2eb26a6e \
    --out skill/validation/audio_summary.json
```

接口审计应报告 `RESULT: PASS`，音频数据审计应报告 `"check": "PASS"`。这验证的是本包内固定输入与软件处理的可复现性，不代表新硬件工程自动正确。

要观察参数修复的差异，可分别读取：

```bash
python3 - <<'PY'
import sys
sys.path.insert(0, 'skill/tools')
from overlay_audit import read_hwh
for path in ['skill/validation/pynq_z2/old_dma14.hwh',
             'skill/examples/rs555_case/rs555_final.hwh']:
    ip = read_hwh(__import__('pathlib').Path(path))['ips']['axi_dma_audio']
    width = int(ip['params']['C_SG_LENGTH_WIDTH'])
    print(path, width, (1 << width)-1, 4096*4 <= (1<<width)-1)
PY
```

在其他工程中，应先以**已审核的 HWH** 为基线生成契约：

```bash
python3 skill/tools/make_contract.py known_good.hwh --out reviewed_contract.json
```

人工核查 IP 名称、地址、DMA 模式、`C_SG_LENGTH_WIDTH` 后冻结该 JSON，再用它检查之后的新 HWH。不能临时从待验证文件生成契约、再用同一文件给自己判定 PASS；那只能确认数据一致，不能确认满足原设计要求。

若想观察音频，`tools/wav_export.py` 可以把原文件封装为 16-bit 双声道 WAV；这不表示声学质量已有标定。
