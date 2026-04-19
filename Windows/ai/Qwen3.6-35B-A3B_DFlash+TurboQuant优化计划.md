# Qwen3.6-35B-A3B DFlash + TurboQuant+ 综合优化计划

> 制定日期：2026-04-19
> 硬件：RTX 4060 Laptop 8GB VRAM + CPU (Alder Lake, 8线程)
> 模型：Qwen3.6-35B-A3B IQ4_XS (17.5GB, 4.25bpw)

---

## 1. 当前已验证基线

| 配置 | Prefill (pp512) | Decode (tg128) | VRAM | 适用场景 |
|------|-----------------|----------------|------|---------|
| 纯 CPU (ngl=0) | 96.72 t/s | 3.90 t/s | 0 | — |
| GPU + `-ot exps=CPU` + q8_0 KV | 153.27 t/s | **32.31 t/s** | 7324/8188 MiB (~89%) | 日常对话 |
| GPU + turbo4 KV | — | **27.97 t/s** | 更低 | 中长上下文 |
| GPU + turbo3 KV | — | **26.98 t/s** | 更低 | 超长上下文 |

**关键约束：VRAM 已占 89%（7324/8188 MiB），仅剩 ~864 MiB 空闲。**

---

## 2. 两项优化技术对比

| 维度 | DFlash (扩散推测解码) | TurboQuant+ (KV 压缩) |
|------|----------------------|----------------------|
| 原理 | 扩散模型并行猜多个 token，大模型一次验证 | WHT + Lloyd-Max 量化压缩 KV cache |
| 加速机制 | 提高 token 接受率，block 并行生成 | 减少 KV 显存，释放空间给长上下文 |
| 显存影响 | **增加** (~1.2GB Q4 drafter) | **减少** (KV cache 压缩 3.8-7.5x) |
| 适用场景 | 单并发，短-中上下文 | 长上下文，显存受限 |
| MoE 支持 | Qwen3.6-35B-A3B 已有 drafter (Preview) | Qwen3.5-35B MoE 全面验证，Qwen3.6 已实测 |
| 框架集成 | vLLM / SGLang | llama.cpp fork (TheTom/llama-cpp-turboquant) |
| 项目地址 | https://github.com/z-lab/dflash | https://github.com/TheTom/turboquant_plus |

---

## 3. VRAM 预算分析

### 当前标准模式 (q8_0 KV)

| 组件 | 占用 |
|------|------|
| 模型共享权重 (GPU) | ~3.5 GB |
| KV cache (q8_0) | ~1.5 GB |
| CUDA/运行时 | ~2.3 GB |
| **总计** | **~7.3 GB** |
| **空闲** | **~0.86 GB** |

### 加入 DFlash 后

| 组件 | 占用 |
|------|------|
| 模型共享权重 (GPU) | ~3.5 GB |
| KV cache (q8_0) | ~1.5 GB |
| CUDA/运行时 | ~2.3 GB |
| DFlash drafter (Q4 量化) | +1.2 GB |
| **总计** | **~8.5 GB → OOM** |

### 方案：TurboQuant+ 腾空间 + DFlash

| 组件 | 占用 |
|------|------|
| 模型共享权重 (GPU) | ~3.5 GB |
| KV cache (turbo3 V) | ~0.5 GB |
| CUDA/运行时 | ~2.3 GB |
| DFlash drafter (Q4) | ~1.2 GB |
| **总计** | **~7.5 GB** |
| **空闲** | **~0.5 GB (勉强可行)** |

---

## 4. 核心障碍：框架不统一

| 问题 | 说明 |
|------|------|
| TurboQuant+ | 仅在 **llama.cpp** 中实现 (TheTom fork) |
| DFlash | 仅在 **vLLM / SGLang** 中实现 |
| MoE expert offload (`-ot exps=CPU`) | llama.cpp 独有功能，SGLang/vLLM 不支持 |

**结论：当前框架生态下，DFlash 和 TurboQuant+ + MoE expert offload 无法同时使用。**

SGLang/vLLM 在 8GB 显卡上运行 35B MoE 本身就不可行 — 没有 expert offload，模型根本放不下。

---

## 5. 修订后的优化计划

### Phase 1: 优化 TurboQuant+ 配置 (近期，1-2 天)

#### 1.1 测试混合 KV 配置

```bat
:: 方案 A: K 保持 q8_0 + V 用 turbo3 (推荐平衡方案)
D:\ai_tools\turboquant_llama\build\bin\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo3 -ub 2048 ^
  --host 0.0.0.0 --port 11436

:: 方案 B: K 用 turbo4 + V 用 turbo3 (最大压缩)
D:\ai_tools\turboquant_llama\build\bin\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk turbo4 -ctv turbo3 -ub 2048 ^
  --host 0.0.0.0 --port 11436

:: 方案 C: K 用 q8_0 + V 用 turbo4 (保守方案)
D:\ai_tools\turboquant_llama\build\bin\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo4 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```

#### 1.2 基准测试命令

```bat
:: 测试各配置的 prefill 和 decode 速度
D:\ai_tools\turboquant_llama\build\bin\llama-bench.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo3 -ub 2048 ^
  -p 512,1024,2048,4096 -n 128
```

#### 1.3 待记录的基准数据

| 配置 | pp512 (t/s) | tg128 (t/s) | VRAM (MiB) | 最大上下文 | 质量评估 |
|------|-------------|-------------|------------|-----------|---------|
| q8_0/q8_0 (基线) | 153.27 | 32.31 | 7324 | ~8K | 基准 |
| q8_0/turbo4 | ? | ? | ? | ~16K | 待测 |
| q8_0/turbo3 | ? | ? | ? | ~24K | 待测 |
| turbo4/turbo4 | 153.27 | 27.97 | ? | ~32K | 已测 |
| turbo4/turbo3 | ? | ? | ? | ~32K | 待测 |
| turbo3/turbo3 | ? | 26.98 | ? | ~32K+ | 已测 |

#### 1.4 内置优化确认

TurboQuant+ 内置以下 MoE 优化（默认启用）：

| 优化 | 效果 | 状态 |
|------|------|------|
| Sparse V | +22.8% decode at 32K (MoE) | 默认开启，`TURBO_SPARSE_V=0` 关闭 |
| Boundary V | turbo2 V 时保护首尾层，恢复 37-91% 质量 | 配合 turbo2 V 自动启用 |
| Norm correction | PPL +1.6% → +1.1% | 默认开启 |
| Block size 128 | 比 block_size=32 压缩好 12% | 默认 |

---

### Phase 2: 跟踪 DFlash 进展 (中期，1-2 周)

#### 2.1 关键跟踪项

- [ ] DFlash 是否在 llama.cpp 中被社区实现
- [ ] SGLang/vLLM 是否添加了 MoE expert offload 支持
- [ ] DFlash drafter 是否有更小版本（<1B 参数，降低 VRAM 需求）
- [ ] Qwen3.6-35B-A3B DFlash 从 Preview 升级到 Stable

#### 2.2 检查命令

```bash
# 检查 DFlash 更新
git ls-remote --heads https://github.com/z-lab/dflash

# 检查 llama.cpp 社区是否有人在讨论 DFlash
# GitHub Issues: https://github.com/ggml-org/llama.cpp/issues?q=dflash

# 检查 SGLang MoE expert offload
# GitHub Issues: https://github.com/sgl-project/sglang/issues?q=expert+offload
```

#### 2.3 DFlash 性能参考 (Qwen3.5-27B, B200 GPU)

| 数据集 | DFlash 加速 | EAGLE-3 加速 | DFlash 接受长度 |
|--------|------------|-------------|---------------|
| HumanEval | 5.14x | 2.17x | ~5.14 |
| Math500 | 6.08x | 2.05x | ~6.08 |
| GSM8K | 5.15x | 2.23x | ~5.15 |
| MBPP | 4.2x | — | — |
| MT-Bench | 3.0x | — | ~5.0 |

Qwen3.6-35B-A3B DFlash (Preview 基准)：

| 数据集 | 接受长度 |
|--------|---------|
| GSM8K | 6.5 |
| Math500 | 7.2 |
| HumanEval | 6.2 |
| MBPP | 5.6 |
| MT-Bench | 5.0 |

---

### Phase 3: 替代方案 (中期)

#### 3.1 小模型 + DFlash

如果愿意在 8GB 上用 DFlash，可换更小的模型：

| 模型 | 大小 | DFlash drafter | 8GB VRAM | 预期加速 |
|------|------|---------------|---------|---------|
| Qwen3.5-9B | 9B | z-lab/Qwen3.5-9B-DFlash | 轻松放下 | 4-5x |
| Qwen3.5-4B | 4B | z-lab/Qwen3.5-4B-DFlash | 富余 | 4-5x |
| Qwen3-Coder-30B-A3B | 30B MoE | z-lab/Qwen3-Coder-30B-A3B-DFlash | 需 expert offload | 3-4x |

**注意**：Qwen3.5-9B + DFlash 绝对速度可能接近 Qwen3.6-35B 的 32 t/s，但模型能力差距明显。

#### 3.2 三合一终极方案路线图

理想状态下，llama.cpp 同时集成：

```
┌─────────────────────────────────────────┐
│         llama.cpp 三合一优化             │
│                                         │
│  1. MoE Expert Offload (-ot exps=CPU)   │
│     → 8GB 跑 35B 模型                   │
│                                         │
│  2. TurboQuant+ KV Cache 压缩           │
│     → 释放显存给长上下文和 drafter       │
│                                         │
│  3. DFlash 扩散推测解码                 │
│     → 3-5x decode 加速                  │
│                                         │
│  预期结果:                               │
│  32 t/s × 3-5x = 96-160 t/s            │
│  32K+ 上下文不 OOM                      │
└─────────────────────────────────────────┘
```

依赖条件：
- [ ] DFlash 移植到 llama.cpp（社区开发中？）
- [ ] TurboQuant+ 上游合并到 llama.cpp（TheTom 在准备 PR）
- [ ] 两者在 llama.cpp 中兼容运行

---

## 6. 可行路径总结

| 路径 | 可行性 | 预期效果 | 时间 |
|------|--------|---------|------|
| A. 优化 TurboQuant+ 配置 | **立即可行** | 混合 KV 配置，平衡速度和长上下文 | 1-2 天 |
| B. SGLang + DFlash (35B MoE) | **不可行** | 8GB 无 expert offload，模型放不下 | — |
| C. SGLang + DFlash (9B dense) | **可行** | 4-5x 加速，但模型能力降级 | 2-3 天 |
| D. 等 llama.cpp 集成 DFlash | **等待** | 三合一终极方案，96-160 t/s | 1-3 月 |
| E. 升级 16GB VRAM | **硬件升级** | DFlash drafter 直接放下 | 取决于预算 |

---

## 7. 下一步行动

1. **立即执行**：跑混合 KV 配置 benchmark（q8_0 K + turbo3/turbo4 V）
2. **记录数据**：填入 1.3 的基准数据表
3. **更新启动脚本**：根据最佳配置更新 `start_qwen36_longcontext.bat`
4. **定期跟踪**：每周检查 DFlash llama.cpp 移植进展
5. **长期规划**：评估是否升级 16GB VRAM 显卡

---

## 8. 参考链接

| 资源 | 链接 |
|------|------|
| DFlash 项目 | https://github.com/z-lab/dflash |
| DFlash 论文 | arXiv:2602.06036 |
| Qwen3.6-35B-A3B DFlash drafter | https://huggingface.co/z-lab/Qwen3.6-35B-A3B-DFlash |
| TurboQuant+ 项目 | https://github.com/TheTom/turboquant_plus |
| TurboQuant+ llama.cpp fork | https://github.com/TheTom/llama-cpp-turboquant |
| TurboQuant 论文 | arXiv:2504.19874 |
| 部署优化笔记 | D:\ai_tools\Qwen3.6-35B-A3B_部署优化笔记.md |
