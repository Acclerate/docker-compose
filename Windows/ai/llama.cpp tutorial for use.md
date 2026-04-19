# llama.cpp 使用教程（Windows + NVIDIA GPU）

## 一、llama.cpp 是什么？

llama.cpp 是一个用 **C/C++ 实现**的高性能大语言模型推理框架，核心特点：
- 无需 Python，无需云端，**本地运行**
- 支持 **CPU / GPU（CUDA/Vulkan）** 混合推理
- 支持 **GGUF 量化模型**，显著降低内存需求
- 内置 **OpenAI 兼容 API 服务器**

---

## 二、核心程序说明

| 程序 | 用途 |
|---|---|
| `llama-server.exe` | **API 服务器**，提供 OpenAI 兼容接口，供外部应用调用 |
| `llama-cli.exe` | **命令行对话**，交互式聊天 |
| `llama-bench.exe` | **性能基准测试** |
| `llama-quantize.exe` | **模型量化工具**，将 FP16 转为 Q4/Q5/Q8 等 |

---

## 三、llama-server 核心参数详解

### 3.1 基础参数

```
-m,   --model <路径>          GGUF 模型文件路径
      --host <IP>             监听地址（默认 127.0.0.1，用 0.0.0.0 开放外部访问）
      --port <端口>           监听端口（默认 8080）
      --alias <名称>          模型别名，API 返回的模型名
```

### 3.2 上下文与内存

```
-c,   --ctx-size <N>          上下文窗口大小（默认 4096）
                               ↑ 越大能记忆的对话越长，但消耗更多内存
-n,   --n-predict <N>         每次回复最大 token 数（默认 -1 无限）
      --keep <N>              上下文满时保留前 N 个 token（-1 = 全保留）
```

**RTX 4060 8GB + 32GB RAM 建议**：`--ctx-size 16384`（16K）

### 3.3 GPU 相关（关键）

```
-ngl, --n-gpu-layers <N>      加载到 GPU 的层数
                               0 = 纯 CPU，999 = 尽量全放 GPU
      --fit [on|off]          自动检测显存，智能分配 GPU/CPU 层（默认 on）
      --fit-target <MiB>      为系统预留多少显存（默认 1024MB）
-fa,  --flash-attn            启用 Flash Attention 加速（推荐开启）
```

**RTX 4060 8GB 建议**：`-ngl 999 --fit --flash-attn`（让 llama.cpp 自动分配）

### 3.4 MoE 专用参数（Qwen3.6-35B-A3B 必用）

```
      --cpu-moe               将所有 MoE 专家层放在 CPU 上（核心优化！）
      --n-cpu-moe <N>         仅前 N 层的专家放在 CPU
-ot,  --override-tensor       手动指定张量设备（高级用法）
                              例：-ot "exps=CPU"            → 所有专家放 CPU
                              例：-ot "blk.([0-9]|1[0-9]).=CUDA0,exps=CPU"
```

**原理**：MoE 模型每次推理只激活 ~3B 参数，专家层放 CPU 影响不大，但大幅节省显存。

### 3.5 KV 缓存优化

```
      --cache-type-k <类型>   Key 缓存量化（默认 f16）
      --cache-type-v <类型>   Value 缓存量化（默认 f16）
                              可选：q8_0（省 50%），q4_0（省 75%）
```

**建议**：`--cache-type-k q8_0 --cache-type-v q8_0`

### 3.6 采样参数（控制生成质量）

```
      --temp <F>              温度（0.1=确定性，1.0=创意性）
      --top-p <F>             核采样（0.95 常用）
      --top-k <N>             候选 token 数（20 常用）
      --min-p <F>             最小概率阈值（0.0~0.1）
      --repeat-penalty <F>    重复惩罚（1.0=不惩罚，1.1~1.5 常用）
      --presence-penalty <F>  存在惩罚（0~2.0，减少重复输出）
```

**Qwen3.6 推荐配置**：
- 普通对话：`--temp 0.6 --top-p 0.95 --top-k 20`
- 编程/推理：`--temp 1.0 --top-p 0.95 --top-k 40`

### 3.7 性能调优

```
-t,   --threads <N>           CPU 线程数（默认 -1 = 物理核心数）
-b,   --batch-size <N>        批处理大小（默认 2048）
-ub,  --ubatch-size <N>       微批次大小（默认 512）
      --parallel <N>          并发请求数（默认 1）
      --cont-batching         启用连续批处理（多用户场景）
      --jinja                 启用 Jinja 模板（支持 chat template）
      --mlock                 锁定内存，防止被交换到磁盘
      --no-mmap               不使用内存映射（某些场景更稳定）
```

---

## 四、启动示例

### 4.1 Qwen3.6-35B-A3B（RTX 4060 8GB + 32GB RAM）

```powershell
D:\ai_tools\llama.cpp\llama-server.exe ^
  -m D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf ^
  --host 0.0.0.0 --port 8362 ^
  --alias qwen3.6-35b-a3b ^
  --ctx-size 16384 ^
  --n-gpu-layers 999 ^
  --cpu-moe ^
  --fit ^
  --flash-attn ^
  --batch-size 256 --ubatch-size 256 ^
  --cache-type-k q8_0 --cache-type-v q8_0 ^
  --threads 8 ^
  --temp 0.6 --top-p 0.95 --top-k 20 ^
  --jinja
```

### 4.2 小模型（HY-MT1.5-1.8B，全 GPU）

```powershell
D:\ai_tools\llama.cpp\llama-server.exe ^
  -m D:\ai_models\models\blobs\sha256-9241336acfa2b1df3511ccbf3f4a9791454b77c40139af11f3a73bc8fc888813 ^
  --host 0.0.0.0 --port 8361 ^
  --n-gpu-layers 99 ^
  --ctx-size 2048 ^
  --flash-attn --jinja
```

---

## 五、API 接口调用

启动后即可通过 HTTP 调用，**完全兼容 OpenAI 格式**：

```bash
# 查看可用模型
curl http://localhost:8362/v1/models

# 对话
curl http://localhost:8362/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-35b-a3b","messages":[{"role":"user","content":"你好"}]}'
```

### Python 调用

```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8362/v1", api_key="none")
resp = client.chat.completions.create(
    model="qwen3.6-35b-a3b",
    messages=[{"role":"user","content":"你好"}]
)
print(resp.choices[0].message.content)
```

**Cherry Studio / 其他客户端接入**：API Base URL 填 `http://localhost:8362/v1`，API Key 随意。

---

## 六、量化格式选择速查

| 量化 | 大小比例 | 质量 | 适用场景 |
|---|---|---|---|
| Q2_K | 最小 | 较差 | 内存极度紧张 |
| Q3_K_M | 较小 | 可用 | 低内存 |
| **IQ4_XS** | **中等** | **好** | **8GB VRAM 推荐** |
| Q4_K_M | 中等 | 好 | 通用选择 |
| Q5_K_M | 较大 | 很好 | 16GB+ VRAM |
| Q8_0 | 大 | 极好 | 24GB+ VRAM |
| BF16 | 原始大小 | 完美 | 48GB+ VRAM |

---

## 七、常见问题

| 问题 | 原因 | 解决方案 |
|---|---|---|
| CUDA out of memory | 模型太大超出显存 | 减少 `-ngl` 或加 `--cpu-moe` |
| 生成速度太慢 | 太多层在 CPU | 增加 `-ngl` 或用更小的量化 |
| 回复重复/无限 | 缺少采样惩罚 | 加 `--presence-penalty 1.5` |
| 上下文溢出 | ctx-size 设太大 | 降低 `--ctx-size` |
| 输出乱码 | 缺少 chat template | 加 `--jinja` |
