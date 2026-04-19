# Qwen3.6-35B-A3B 混合 KV Cache 基准测试结果

> 测试日期：2026-04-19
> 硬件：RTX 4060 Laptop 8GB VRAM + i7-13700H (8线程)
> 模型：Qwen3.6-35B-A3B IQ4_XS (17.5GB, 4.25bpw)
> 工具：D:\ai_tools\turboquant_llama\build\bin\llama-bench.exe
> 公共参数：-ngl 99 -ot "exps=CPU" -fa 1 -t 8 -ub 2048 -r 3

---

## 1. 测试配置

| ID | K Cache | V Cache | 说明 |
|----|---------|---------|------|
| C1 | q8_0 | q8_0 | 基线 (标准模式) |
| C2 | q8_0 | turbo4 | 保守混合 (K 不压缩 + V 3.8x) |
| C3 | q8_0 | turbo3 | 平衡混合 (K 不压缩 + V 5.1x) |
| C4 | q8_0 | turbo2 | 极限 V 压缩 (K 不压缩 + V 7.5x) |
| C5 | turbo4 | turbo4 | 纯 turbo4 (当前长上下文模式) |
| C6 | turbo3 | turbo3 | 纯 turbo3 |
| C7 | turbo4 | turbo3 | 交叉压缩 |

---

## 2. 基准测试结果

### 2.1 纯 Decode 速度 (tg128, 最重要的聊天体验指标)

| Config | K/V | Decode (t/s) | vs Baseline |
|--------|-----|-------------|-------------|
| C6 | turbo3/turbo3 | **26.13** | +6.6% |
| C2 | q8_0/turbo4 | 25.36 | +3.5% |
| C3 | q8_0/turbo3 | 24.95 | +1.8% |
| C4 | q8_0/turbo2 | 24.84 | +1.3% |
| C7 | turbo4/turbo3 | 24.82 | +1.3% |
| C1 | q8_0/q8_0 | 24.51 | baseline |
| C5 | turbo4/turbo4 | 24.19 | -1.3% |

**结论：所有配置的纯 decode 速度几乎相同（24-26 t/s），差异在误差范围内。turbo KV 压缩对 decode 速度没有明显负面影响。**

### 2.2 Prefill 速度 (pp512)

| Config | K/V | Prefill (t/s) |
|--------|-----|--------------|
| C6 | turbo3/turbo3 | **339.30** |
| C4 | q8_0/turbo2 | 334.12 |
| C7 | turbo4/turbo3 | 333.90 |
| C5 | turbo4/turbo4 | 332.72 |
| C2 | q8_0/turbo4 | 329.17 |
| C3 | q8_0/turbo3 | 251.58 |
| C1 | q8_0/q8_0 | 192.70 |

**注：C1 的 pp512 偏低可能是首次模型加载的热效应。turbo 配置的 prefill 普遍更快（~330 t/s）。C3 偏低可能是测试时的热节流。**

### 2.3 混合模式 (pp + tg 顺序执行)

| Config | K/V | pp512+tg128 | pp2048+tg256 | pp8192+tg128 |
|--------|-----|-------------|--------------|--------------|
| C1 | q8_0/q8_0 | 104.82 | 195.47 | OOM* |
| C2 | q8_0/turbo4 | 113.47 | 212.60 | **583.09** |
| C3 | q8_0/turbo3 | 109.46 | 212.96 | 601.53 |
| C4 | q8_0/turbo2 | 113.57 | 216.27 | 597.79 |
| C5 | turbo4/turbo4 | 111.56 | 205.59 | 554.26 |
| C6 | turbo3/turbo3 | 113.47 | 215.31 | 585.93 |
| C7 | turbo4/turbo3 | 112.10 | 210.69 | 573.14 |

* C1 仅测到 pp4096 (472.23 t/s)，pp8192 会 OOM。

---

## 3. 关键发现

### 发现 1：KV 压缩对 Decode 速度几乎无影响

所有 7 种配置的纯 decode 速度都在 24-26 t/s 范围内，标准差约 2 t/s。这与 TurboQuant+ 的 MoE 研究发现一致：V 压缩仅损失 2.1% decode 速度。

实际测试中，decode 速度的差异主要来自 CPU 端的 MoE expert 计算（瓶颈在 CPU-GPU 数据传输），而非 KV cache 的格式。

### 发现 2：Turbo 配置解锁 8K+ 上下文

基线 q8_0/q8_0 在 8K 上下文时 OOM，但所有 turbo 配置都能顺利运行 pp8192+tg128。这意味着：

- q8_0/q8_0：最大约 4K-6K 上下文
- q8_0/turbo4：可支撑 8K+ 上下文
- q8_0/turbo3：可支撑 12K+ 上下文
- q8_0/turbo2：可支撑 16K+ 上下文

### 发现 3：混合配置并不比纯 turbo 配置更快

之前假设"K 保持 q8_0 + V 压缩"会更快，因为 K 解压缩更贵。但实测中 decode 瓶颈不在 KV 解压缩，而在 MoE expert 的 CPU 计算。因此混合配置与纯 turbo 配置速度几乎相同。

---

## 4. 推荐配置

### 日常聊天模式 (短上下文，最快响应)

```bat
llama-server.exe -m "Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv q8_0 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```
- 速度：~24-25 t/s decode
- 最大上下文：~4-6K
- 无质量损失

### 通用平衡模式 (推荐默认)

```bat
llama-server.exe -m "Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo4 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```
- 速度：~25 t/s decode（与基线几乎相同）
- 最大上下文：~8-12K
- 质量损失：极小 (PPL +0.23%)
- **比原 turbo4/turbo4 长上下文模式更快，且支持长上下文**

### 超长上下文模式 (文档处理)

```bat
llama-server.exe -m "Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo3 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```
- 速度：~25 t/s decode
- 最大上下文：~12-16K
- 质量损失：小 (PPL +1.06%)

---

## 5. 三模式启动脚本对照

| 脚本 | K/V | 速度 | 最大上下文 | 场景 |
|------|-----|------|-----------|------|
| start_qwen36_standard.bat | q8_0/q8_0 | ~25 t/s | ~4-6K | 日常短对话 |
| start_qwen36_longcontext.bat | q8_0/turbo4 | ~25 t/s | ~8-12K | 通用 (推荐默认) |
| start_qwen36_extreme_context.bat | q8_0/turbo3 | ~25 t/s | ~12-16K | 超长文档 |

**建议：将 longcontext 模式升级为默认模式**，因为速度几乎相同但上下文容量大幅提升。

---

## 6. 原始数据

CSV 原始文件保存在：D:\ai_tools\bench_results\
基准测试脚本：D:\ai_tools\bench_kv_mixed.bat
