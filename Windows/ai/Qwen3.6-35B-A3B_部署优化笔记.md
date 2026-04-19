# Qwen3.6-35B-A3B 本地部署优化笔记

> 硬件：RTX 4060 Laptop 8GB VRAM + CPU (Alder Lake, 8线程)
> 系统：Windows 11 Pro
> 模型：Qwen3.6-35B-A3B IQ4_XS (17.5GB, 4.25bpw)

---

## 1. 模型信息

| 项目 | 值 |
|------|-----|
| 架构 | MoE (Mixture of Experts) |
| 总参数 | 34.66B |
| 每token激活参数 | ~3B |
| 量化 | IQ4_XS (4.25 bpw) |
| 文件 | `D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf` |

---

## 2. 关键优化：MoE 专家层 CPU 卸载

**核心原理**：MoE 模型每次推理只激活 3B 参数。把注意力层放 GPU（小而计算密集），专家权重放 CPU（大但稀疏访问）。

参数说明：
- `-ngl 99`：所有层标记为 GPU
- `-ot "exps=CPU"`：专家张量强制放 CPU
- `-fa 1`：Flash Attention 减少显存占用
- `-ctk q8_0 -ctv q8_0`：KV cache 量化为 q8_0，省 50% 显存给上下文
- `-ub 2048`：增大微批次，加速 prompt 处理

**优化效果：**

| 配置 | pp512 (t/s) | tg128 (t/s) | 提升倍数 |
|------|-------------|-------------|---------|
| 纯 CPU (ngl=0) | 96.72 | 3.90 | 基准 |
| GPU + MoE CPU卸载 | 153.27 | **32.31** | **8.3x** |
| 实际服务运行 | — | **35.6** | **9.1x** |

VRAM 使用：7324/8188 MiB (~89%)

---

## 3. TurboQuant+ 长上下文模式

TurboQuant+ 是 Google ICLR 2026 论文的实现（[GitHub](https://github.com/TheTom/turboquant_plus)），通过 Walsh-Hadamard 变换 + Lloyd-Max 量化将 KV cache 极限压缩。

| KV 类型 | 压缩率(vs f16) | tg128 (t/s) | 适用场景 |
|---------|---------------|-------------|---------|
| q8_0 | 1.9x | 24.51 | 短上下文对话 |
| turbo4 | 3.8x | 24.19 | 中长上下文 |
| turbo3 | 5.1x | 26.13 | 超长上下文 |

**混合 KV 配置（推荐）**：K 保持 q8_0 + V 用 turbo 压缩

| 混合配置 | V 压缩率 | tg128 (t/s) | 最大上下文 |
|---------|---------|-------------|-----------|
| q8_0/turbo4 | 3.8x (V) | 25.36 | ~8-12K |
| q8_0/turbo3 | 5.1x (V) | 24.95 | ~12-16K |
| q8_0/turbo2 | 7.5x (V) | 24.84 | ~16K+ |

**关键发现（2026-04-19 基准测试）**：所有 KV 配置的 decode 速度几乎相同（24-26 t/s），瓶颈在 MoE expert 的 CPU 计算。Turbo 配置的优势在于释放显存以支撑更长上下文，而非提升速度。

详细测试数据见：`D:\ai_tools\Qwen3.6-35B-A3B_混合KV基准测试结果.md`

---

## 4. 三模式启动脚本

| 脚本 | 路径 | KV 配置 | 速度 | 最大上下文 | 场景 |
|------|------|---------|------|-----------|------|
| 标准模式 | `D:\ai_tools\start_qwen36_standard.bat` | q8_0/q8_0 | ~25 t/s | ~4-6K | 日常短对话 |
| 长上下文 | `D:\ai_tools\start_qwen36_longcontext.bat` | q8_0/turbo4 | ~25 t/s | ~8-12K | 通用 (推荐默认) |
| 超长上下文 | `D:\ai_tools\start_qwen36_extreme_context.bat` | q8_0/turbo3 | ~25 t/s | ~12-16K | 超长文档 |

所有脚本共用端口 **11436**，不能同时运行。

### 标准模式完整命令
```bat
D:\ai_tools\llama.cpp\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv q8_0 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```

### 长上下文模式完整命令 (混合 KV，推荐默认)
```bat
D:\ai_tools\turboquant_llama\build\bin\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo4 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```

### 超长上下文模式完整命令
```bat
D:\ai_tools\turboquant_llama\build\bin\llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 -ot "exps=CPU" -fa 1 -t 8 ^
  -ctk q8_0 -ctv turbo3 -ub 2048 ^
  --host 0.0.0.0 --port 11436
```

---

## 5. Cherry Studio 配置

1. **设置 → 模型提供商** → 添加自定义提供商
   - 名称: `Local Qwen3.6`
   - API 地址: `http://localhost:11436/v1`
   - API 密钥: `sk-local`（随意填，不验证）
2. **模型管理** → 手动添加模型
   - 名称: `Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf`
3. **推荐参数**：

| 参数 | 值 |
|------|-----|
| Temperature | 0.6 |
| Top-P | 0.95 |
| Top-K | 20 |
| Min-P | 0.0 |
| Repeat Penalty | 1.05 |
| Presence Penalty | 1.0 |
| Max Tokens | 8192 |

> 这是 thinking 模型，回答前会输出思考过程。不需要思考时在 system prompt 加 `/no_think`。

---

## 6. 工具链路径

| 工具 | 路径 |
|------|------|
| 原版 llama.cpp | `D:\ai_tools\llama.cpp\` |
| TurboQuant+ fork | `D:\ai_tools\turboquant_llama\` |
| 模型文件 | `D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf` |
| VS Build Tools 2026 | `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\` |
| CUDA Toolkit 12.9 | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.9\` |

---

## 7. 已验证的结论

- **ik_llama.cpp**：在 Windows + MSVC 2026 上比原版预编译慢（MSVC 2026 是 CUDA 12.9 不支持的编译器），已删除
- **自编译 vs 预编译**：预编译版通常更快（编译器版本兼容性更好）
- **-ncmoe vs -ot exps=CPU**：`-ot exps=CPU` 更快（32 vs 27 t/s）
- **KV 量化对短上下文速度无帮助**，但对长上下文防止 OOM 至关重要
- **混合 KV 配置实测有效**：q8_0 K + turbo V 不影响 decode 速度，但大幅提升最大上下文
- **所有 KV 配置 decode 速度相近**（24-26 t/s），瓶颈在 MoE expert CPU 计算，不在 KV 解压缩
- **推荐默认使用 q8_0/turbo4**：速度与 q8_0/q8_0 相同，但支持 8K+ 上下文
