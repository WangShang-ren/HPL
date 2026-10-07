## 二、HPL

### 2.1 项目理解
- 项目：HPL（High-Performance Linpack）
- 链接：
- 主要内容：
1. 建立稳定运行并通过正确性检查的 HPL Baseline；
2. 分析 HPL 性能受到的主要因素；
3. 分别测试：
   - OpenBLAS 线程数；
   - MPI 进程数；
   - MPI 进程拓扑 `P × Q`；
   - HPL block size `NB`；
   - 编译器优化选项；
   - CPU binding；
   - NUMA；
4. 根据实验结果确定最终配置；
5. 比较 Baseline 与优化后的性能；
6. 分析性能提升来自哪里；
7. 总结可迁移到其他 HPC 程序的优化规律。
任务目标：

- 下载 HPL 源码。
- 配置 HPL 运行环境，包括编译器、MPI 和 BLAS 库。
- 编译并运行 HPL。
- 修改 HPL.dat 参数文件。
- 至少测试 3 组不同参数。
- 记录每组参数的运行结果。
- 对比不同参数对性能的影响。
- 选择表现最好的一组参数，并说明原因。

### 2.2 机器环境

#### 2.2.1 硬件
| **项目** | **内容** |
| --- | --- |
| **机器来源** | WSL2 (Windows Subsystem for Linux 2) |
| **操作系统** | Ubuntu  |
| **CPU** | AMD Ryzen 7 7840HS w/ Radeon 780M Graphics (8核16线程)(8C/16T) |
| **内存** | 16GB |
| **GPU** | 无  |
| **编译器** | g++ (GCC), CMake |
| L3 Cache | 16 MiB |
| NUMA | 单 NUMA node |

CPU为Zen 4 架构

#### 2.2.2 软件
| 项目 | 版本/状态 |
|---|---|
| OS | WSL2 Ubuntu |
| Kernel | 6.18 |
| GCC | 15.2 |
| GFortran | 15.2 |
| OpenMPI | 5.0.10 |
| OpenBLAS | 0.3.32 |
| OpenBLAS threading | pthread |
| MKL | 无 |
| BLIS | 无 |
| perf | 无 |
| numactl | 无 |

### 2.3 项目复现和基础分析

#### 2.3.1 HPL 计算结构
HPL 求解稠密线性方程组：Ax=b 其中： A\in R^{N× N} 主要计算量来自： O(N^3) 因此 HPL 的主要性能通常受到：

- DGEMM；
- BLAS；
- MPI；
- Panel Factorization；
- Block Size；
- CPU 并行度；
等因素影响。 ---

#### 2.3.2 Baseline

##### 2.3.2.1 Baseline Definition
本实验 Baseline 定义为： Compiler : mpicc Optimization : -O2 BLAS : OpenBLAS Fortran symbol convention : F2C -DAdd_ HPL_OPTS : empty N : 8000 NB : 192 MPI : np=1 P × Q : 1 × 1 OpenBLAS threads : default 顶层 `Make.top` 不作为性能优化对象。 主要修改： Make.Linux_Intel64 用于指定：

- `TOPdir`
- MPI compiler
- BLAS
- Compiler
- Linker
其中：TOPdir=/home/user/HPC/hpl

##### 2.3.2.2 Baseline 执行条件
主要测试规模： N = 8000 NB = 192 P = 1 Q = 1 MPI ranks = 1 正确性标准：PASSED

##### 2.3.2.3 Baseline 正确性
Baseline 在： N = 8000下能够正常完成 HPL，并通过：因此该配置可以作为后续优化实验的有效基线。

##### 2.3.2.4 Baseline 性能
N=8000：

| Run | GFLOPS | Correctness |
|---|---:|---|
| 1 | 95.15 | PASSED |
| 2 | 100.63 | PASSED |
| 3 | 100.42 | PASSED |
| **Average** | **98.73** | PASSED |
| **Best** | **100.63** | PASSED |

因此 Baseline 定义为：98.73GFLOPS;Best baseline：100.63 GFLOPS

##### 2.3.2.5 Baseline 规模验证
为了避免只在单一规模上优化，本实验额外测试了不同规模。

| 规模 | N | GLOPD | 结果 |
| :--- | :--- | :--- | :--- |
| 小规模 | N = 2000 | 73.88 GFLOPS | PASSED |
| 中等规模 | N = 6000 / MPI ranks = 4 | 7.42 GFLOPS | PASSED |

中等规模结果明显低于预期。 进一步分析发现该配置属于： **MPI + CPU oversubscription / 并行资源配置不合理** 因此它被作为反例，而不是作为性能结果进行优化。

### 2.4 项目优化

#### 2.4.1 优化实验设计
本实验采用**单因素控制变量 + 组合优化**的方式。 主要实验变量： OpenBLAS threads MPI ranks P × Q NB Compiler optimization CPU binding NUMA

#### 2.4.2 OpenBLAS 线程实验

##### 2.4.2.1 实验目的
研究单进程情况下 OpenBLAS 多线程对 HPL 的影响。 CPU：8 physical cores；16 logical threads 测试：T = 1 / 2 / 4 / 8 / 16

##### 2.4.2.2 实验结果
结果：

| OpenBLAS Threads | GFLOPS |
|---:|---:|
| 1 | 53.3 |
| ... | ... |
| 8 | **184.6** |
| 16 | **85.5** |

SMT 反例 HPL/OpenBLAS 的计算瓶颈并不会因为逻辑线程翻倍而自动获得性能提升。 对于 DGEMM 等高计算密度工作负载，物理核心已经能够充分占用主要执行资源。继续增加 SMT 线程反而会造成：

- FPU/执行资源竞争；
- cache/resource contention；
- thread scheduling overhead。

#### 2.4.3 MPI 进程与 OpenBLAS 线程组合
配置： np=1, T=8; np=2, T=4; np=4, T=2; np=8, T=1;

##### 2.4.3.1 实验结果
| MPI ranks | Threads/rank | P×Q | GFLOPS |
|---:|---:|---:|---:|
| 1 | 8 | 1×1 | 214.8 |
| 4 | 2 | 1×4 | **221.1** |
| 8 | 1 | 1×8 | 219.8 |

#### 2.4.4 MPI Process Grid：P × Q
HPL 并不是简单地“MPI 越多越好”。 二维进程网格： Q 会影响：

- matrix block distribution；
- communication；
- panel factorization；
- broadcast；
- synchronization。
实验测试不同： P × Q 组合。

##### 2.4.4.1 实验结论
在当前单机、8 物理核环境下： P=1, Q=4 明显优于: P=2,Q=2 P=4,Q=1 规律：P小,Q大;表现更好。

##### 2.4.4.2 原因分析
HPL 的 panel factorization 对进程组织方式较敏感。当前实验中：P 较大会增加 panel factorization 相关的同步/通信路径。 因此P=1,Q=4能够减少该方向上的额外开销。 在多节点环境中，随着网络通信成本变化，最优 `P×Q` 可能发生变化。

#### 2.4.5 NB Block Size 实验
HPL 的： NB参数 控制 block size。 测试：NB = 64//96/128/192/256/384

##### 2.4.5.1 实验结果
关键结果： NB=64 → 182 GFLOPS NB=256 → 214.4 GFLOPS 因此： 182→214.4 提升： +17.6%

#### 2.4.6 NB 与 Cache 的关系
CPU： L3 = 16 MiB 在： NB=256 附近，HPL panel/block 工作集与 L3 cache 的关系较为合适。 实验结果显示： NB=64 block 太小，DGEMM 计算块偏瘦，增加下列问题：

- block management；
- loop overhead；
- kernel 调用；
- cache reuse 不充分；
NB=256能够获得更好的计算效率。 因此：成为当前平台的最佳测试值。

#### 2.4.7 Compiler Optimization 实验
测试： -O2 -O3 -O3 -march=native

##### 2.4.7.1 实验结果
| Compiler | GFLOPS |
|---|---:|
| `-O2` | 206.5 |
| `-O3` | 212.9 |
| `-O3 -march=native` | 212.4 |

Compiler optimization 有收益，但不是当前 HPL 性能提升的主要来源。 主要计算位于：OpenBLAS DGEMM 因此 HPL 本身 C/Fortran 层代码占整体计算量的比例较低。

#### 2.4.8 CPU Binding 实验
测试： 不绑定 与： --bind-to core --map-by core OMP_PROC_BIND=TRUE

##### 2.4.8.1 实验结果
典型结果： 218.0 → 226.1 GFLOPS 提升： 226.1-218.0/218.0 ≈3.7% 因此： CPU Binding +3.7% ---

#### 2.4.9 NUMA 实验
当前环境： 1 NUMA node 因此不存在跨 NUMA node 的优化空间。 此外： numactl 在当前环境不可用。 因此本实验： NUMA optimization = Not tested 不能将其写成“NUMA 优化没有收益”。 准确表述应该是：

> 当前平台为单 NUMA node，且缺少 `numactl`，因此没有进行多 NUMA node affinity 实验。

#### 2.4.10 BLAS Library 对比
理论上： OpenBLAS、 BLIS、 MKL、 AOCL、 等 BLAS 实现可能产生明显性能差异。 但当前环境： MKL unavailable BLIS unavailable 系统 BLAS alternative 最终仍指向： OpenBLAS 因此： BLAS library comparison = Not tested 这一项不能作为本次优化收益来源。

#### 2.4.11 最终配置
综合：

- OpenBLAS threading；
- MPI rank；
- process grid；
- NB；
- Compiler；
- CPU binding；
得到最终配置： Compiler: -O3 -march=native -mtune=native BLAS: OpenBLAS NB: 256 MPI: np=4 OpenBLAS: 2 threads/rank Process Grid: P=1 Q=4 Binding: --bind-to core --map-by core OpenMP: OMP_PROC_BIND=TRUE

#### 2.4.12 Final Run Command
最终运行命令： bash cd /home/user/HPC/hpl/bin/Linux_Intel64 OPENBLAS_NUM_THREADS=2 OMP_PROC_BIND=TRUE mpirun -np 4 --oversubscribe --bind-to core --map-by core ./xhpl

#### 2.4.13 Final Performance
//一个一个尝试去优化，最后总结找到一个目前比较理想的规模和结果

##### 2.4.13.1 N=8000
最终配置重复运行 202.1 GFLOPS 184.1 GFLOPS 189.2 GFLOPS 平均： 191.83 GFLOPS 同时历史最佳： 226.16 GFLOPS 均PASSED

##### 2.4.13.2 N=12000
测试： N=12000 结果： 206.0 GFLOPS 并： PASSED 说明最终配置不仅能够在 N=8000 工作，而且能够扩展到更大的问题规模。

#### 2.4.14 Speedup
Baseline： 98.73 GFLOPS Final best： 226.16 GFLOPS 因此： Speedup= 226.16/98.73 得到： 2.29× 即： +129.1%

##### 2.4.14.1 保守平均口径
如果使用 Final 三次运行平均： 191.83 GFLOPS 则： 191.83/98.73 ≈1.94 即： 1.94× 对应： +94.3% 因此报告中建议同时保留：

> **Best speedup：2.29×**
以及：

> **Final repeated-run average speedup：1.94×**
这样比只报告最高分更加严谨。

#### 2.4.15 性能收益拆解
需要特别注意：

> `226.16 / 98.73 = 2.29×` 并不意味着每一个优化因素分别贡献了固定比例的性能。
因为这些因素存在明显交互。 当前实验可以定性拆分为：

##### 2.4.15.1 第一层：线程配置
从： 错误/默认线程配置 转向： 8 physical cores 带来了最大的性能变化。 这是本实验最重要的发现之一。

##### 2.4.15.2 第二层：MPI + OpenBLAS 混合并行
最终： 4 MPI ranks × 2 BLAS threads 优于： 1 MPI × 8 threads 说明 HPL 并非简单地使用一个多线程 BLAS 就能达到最佳性能。

##### 2.4.15.3 第三层：NB
NB=64 → NB=256 约： +17.6% 说明 cache/blocking 与 DGEMM kernel 形状非常重要。

##### 2.4.15.4 第四层：Binding
约： +3.7% 属于相对较小但成本极低的优化。

##### 2.4.15.5 第五层：Compiler
约： +3.1% 说明 compiler optimization 有收益，但不是主要瓶颈。

#### 2.4.16 主要性能瓶颈
根据实验结果，目前可以总结三个主要瓶颈。

##### 2.4.16.1 DGEMM / OpenBLAS 线程配置
最重要的问题是： MPI processes× BLAS threads 必须与 CPU 物理资源匹配。 本实验中： 8 physical cores 因此： NP × T ≈ 8 是一个非常有效的经验约束。 错误配置可能导致： oversubscription FPU contention cache contention 最终性能下降。

#### 2.4.17 Panel Factorization
第二个瓶颈来自 HPL 的： Panel Factorization 尤其在： P 增大时，panel 相关同步和通信成本更加明显。 这解释了当前环境下： P=1,Q=4 优于： P=2,Q=2 P=4,Q=1

#### 2.4.18 Block Size / Cache / DGEMM
第三个主要因素是： NB NB 决定 HPL 如何把矩阵组织成 block。 它同时影响： Cache reuse DGEMM shape Panel factorization Communication granularity 本实验： NB=64 → 182 GFLOPS NB=256 → 214.4 GFLOPS 证明：

> HPL 的 NB 并不是一个纯粹的“越小通信越少 / 越大计算越快”的单调参数，而是需要与 CPU cache 和 BLAS kernel 配合。

#### 2.4.19 Amdahl's Law 视角
HPL 的绝大部分计算由： DGEMM / BLAS 完成。 因此 HPL 本身的 C/Fortran 代码优化空间受到 Amdahl's Law 限制。 如果： HPL framework overhead ≈ small fraction 那么即使将 HPL 自身代码优化很多，整体性能提升仍然有限。 所以：-O2 → -O3只有约： +3.1% 而线程和 BLAS 配置却可以产生远大得多的收益。

#### 2.4.20 正确性
本实验所有作为正式性能结果使用的运行均要求： PASSED 已验证： N=2000 PASSED N=6000 PASSED N=8000 PASSED N=12000 PASSED 因此性能结果不能只看 GFLOPS，而必须同时满足： Performance + Correctness

#### 2.4.21 当前实验限制
本实验存在以下限制。

##### 2.4.21.1 单机环境
当前只测试： AMD Ryzen 7 7840HS 因此不能推导出：

> 最优 HPL 参数适用于所有 CPU。

##### 2.4.21.2 没有 MKL / BLIS
当前无法进行： OpenBLAS vs MKL OpenBLAS vs BLIS 的直接比较。

##### 2.4.21.3 没有 perf
由于当前 WSL 环境没有： perf 无法直接观察：

- cache miss；
- branch miss；
- cycles；
- instructions；
- FLOPS counters；
因此当前瓶颈分析主要来自：

> 参数扫描 + 性能曲线 + HPL 算法结构。

##### 2.4.21.4 单 NUMA Node
当前 CPU 只有： 1 NUMA node 所以无法研究： NUMA locality remote memory multi-socket affinity

#### 2.4.22 后续优化方向
如果继续进行 HPL 优化，可以按照以下优先级：

##### 2.4.22.1 Priority 1
安装/测试真正不同的 BLAS：BLIS、MKL

##### 2.4.22.2 Priority 2
继续探索和优化 HPL 参数：BCAST、PFACT、DEPTH、NBMIN

##### 2.4.22.3 Priority 3
扩大问题规模：N=16000；N=20000+ 观察： NB cache memory bandwidth 在大规模问题下是否发生变化。

##### 2.4.22.4 Priority 4
原生 Linux 环境： perf numactl 进一步进行硬件级 profiling。

##### 2.4.22.5 Priority 5
多节点环境 进一步研究： P × Q MPI communication network 并探究：

> 为什么单机最优的 `P=1,Q=4` 并不一定是多节点环境的最优配置。

#### 2.4.23 主要实验结论
本实验最终得到： 98.73 → 226.16 GFLOPS 2.29× 最高性能提升。 保守采用 Final 三次运行平均： 1.94× 最重要的三个经验：

##### 2.4.23.1 ① 并行资源必须匹配
MPI× BLAS\ Threads≈ Physical\ Cores

##### 2.4.23.2 ③ NB 必须和 Cache / BLAS kernel 配合
当前平台：NB=256明显优于：NB=64

#### 2.4.24 HPC 学习收获
本实验涉及的核心 HPC 知识：

HPL
├── MPI
│   ├── MPI Rank
│   ├── Process Grid
│   └── P × Q
│
├── BLAS
│   └── DGEMM
│
├── Multithreading
│   ├── OpenBLAS threads
│   └── MPI × Thread hybrid parallelism
│
├── CPU Architecture
│   ├── Physical Core
│   ├── SMT
│   ├── FPU
│   └── Cache
│
├── Memory
│   └── L3 Cache
│
├── Optimization
│   ├── Compiler
│   ├── NB
│   └── CPU Binding
│
└── Performance Analysis
    ├── Baseline
    ├── Parameter Sweep
    ├── Correctness
    └── Speedup
其中最值得进一步掌握的概念：

> **MPI + OpenMP/BLAS hybrid parallelism → Cache → Blocking → DGEMM → CPU binding → Profiling**

#### 2.4.25 可复现性
实验目录： /home/user/HPC/hpl 主要交付： bin/Linux_Intel64/xhpl HPL.dat Make.Linux_Intel64 HPL_OPTIMIZATION_REPORT.md experiments/ scripts/ 其中： experiments/ 保存各组实验的： log dat 等原始结果。 scripts/ 用于实验复现。

#### 2.4.26 最终配置摘要
| 项目 | Baseline | Final |
|---|---|---|
| Compiler | `-O2` | `-O3 -march=native -mtune=native` |
| BLAS | OpenBLAS | OpenBLAS |
| MPI ranks | 1 | 4 |
| BLAS threads | default | 2 |
| P × Q | 1×1 | 1×4 |
| NB | 192 | 256 |
| Binding | default | core |
| N | 8000 | 8000 |
| GFLOPS | **98.73 avg** | **191.83 avg** |
| Best GFLOPS | 100.63 | **226.16** |
| Speedup | 1× | **2.29× best** |
| Correctness | PASSED | PASSED |

#### 2.4.27 最终结论
本实验通过系统的参数搜索和控制变量实验，对 HPL 在 AMD Ryzen 7 7840HS 单机环境上的性能进行了优化。 最终性能由： 98.73 GFLOPS 提高至最高： 226.16 GFLOPS 获得： 2.29× 的最高加速比。重复运行的最终配置平均达到： 191.83 GFLOPS 对应： 1.94× 的平均加速比。 实验表明，本次性能提升的来源是：

1. **合理配置 MPI rank 与 OpenBLAS threads；**
2. **选择合适的 MPI process grid；**
3. **选择与 CPU cache 和 DGEMM kernel 相匹配的 NB；**
4. **通过 CPU binding 减少线程迁移和资源竞争。**
经验是： NP× T≈ N(physical cores) 以及： HPL 参数必须与底层 BLAS、CPU Cache 和并行拓扑共同考虑
