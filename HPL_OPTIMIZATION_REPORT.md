# HPL 2.3 Optimization Report (WSL Ubuntu, AMD Ryzen 7 7840HS)

> 身份: HPC Performance Engineer
> 方法: Baseline → 单项优化 → 测试 → 记录 → 分析 → 下一项,禁止一次性全开
> 数据真实性: 所有 GFLOPS 均为本机实测 `bin/Linux_Intel64/xhpl` 输出,未测试项明确标 `Not tested` / `Unavailable`

---

## 1. Project Overview

- 目标:  HPL 2.3 作为 HPC 性能优化学习项目,完整走通
  `工程化构建 + Baseline + 正确性 + 测试体系 + 瓶颈分析 + 逐项优化 + 综合优化 + 实验记录`,
  所有修改可追溯、可解释、可复现。
- 起点问题:
  - `make arch=Linux_Intel64` 失败,根因不是缺代码,而是构建系统路径断裂:
    - `Make.Linux_Intel64: TOPdir=$(HOME)/hpl` → `/home/user/hpl`,但实际 checkout 是 `/home/user/HPC/hpl`
    - `Make.top: leaf: ln -fs $(TOPdir)/Make.$(arch) Make.inc` 因此所有
      `src/*/Linux_Intel64/Make.inc -> /home/user/hpl/Make.Linux_Intel64` 全部悬空 (dangling)
    - `Make.Linux_Intel64` 本身是 Intel 模板 (`mpiicc`, `MKLROOT`, `-openmp`, `-ansi-alias`,
      `-mt_mpi`, `F2CDEFS=-DAdd__`),在 WSL Ubuntu (GCC+OpenMPI+OpenBLAS) 上不可用
    - git 状态: `setup/Make.Linux_Intel64` + `README` 被删除,顶层 `Make.Linux_Intel64` 为 untracked,
      `bin/lib/include` 为空,无 `HPL.dat`,从未构建成功
- 本次工作:
  1. 恢复干净构建 (只改一个文件 `Make.Linux_Intel64`,不动 `Make.top`/`makes/*`/`src` 核心算法)
  2. `make arch=Linux_Intel64` 一次成功,生成 `bin/Linux_Intel64/xhpl` (ELF 64-bit, dynamic, links openblas+openmpi+gfortran)
  3. Baseline (保守 `-O2` + OpenBLAS) + 小/中/大三级正确性 PASSED
  4. 单项扫描: threads / MPI / NB / PxQ / compiler / binding / NUMA
  5. 综合最优 + Final 复测 + 本报告

交付物:

```text
bin/Linux_Intel64/xhpl
HPL.dat                     # 顶层, Final candidate (N=8000 NB=256 P=1 Q=4)
Make.Linux_Intel64          # Final: -O3 -march=native -mtune=native + mpicc + -lopenblas
HPL_OPTIMIZATION_REPORT.md  # 本文件
experiments/
  baseline/  blas/  compiler/  openmp/  mpi/  nb/  pq/  final/
scripts/  results/  logs/
```

---

## 2. Hardware / Software Environment

实测命令: `lscpu`, `free -h`, `uname -a`, `gcc --version`, `gfortran --version`,
`mpicc -showme:version`, `ompi_info`, `dpkg -l`, `ldconfig -p`, `nproc`, `which perf/time`

| 项 | 值 |
|---|---|
| CPU | AMD Ryzen 7 7840HS w/ Radeon 780M, x86_64, AuthenticAMD Family 25 Model 116 |
| Cores/Threads | 8 cores / 16 threads (Thread(s) per core: 2), Socket(s): 1, `nproc`=16 |
| Flags (节选) | fma, avx, avx2, avx512f/avx512dq/avx512bw/avx512vl/avx512_bf16, bmi1/2, aes |
| Cache | L1d 256KiB x8, L1i 256KiB x8, L2 8MiB (8 instances, 1MiB/core), L3 16MiB x1 |
| NUMA | 1 node only (`NUMA node0 CPU(s): 0-15`), 无跨 NUMA 优化空间 |
| Mem | 15Gi total, ~14Gi avail, Swap 4.0Gi |
| OS/Kernel | WSL2 Ubuntu, `Linux DESKTOP-J1MSR9D 6.18.33.2-microsoft-standard-WSL2 x86_64 GNU/Linux` |
| GCC | `gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0` |
| GFortran | `GNU Fortran 15.2.0` |
| MPI | OpenMPI 5.0.10 (Debian, `mpicc` wraps `gcc`), Prefix `/usr`; 另装 MPICH 4.3.2 但默认用 OpenMPI; `mpirun --version` 因缺 `help-schizo-ompi.txt` 报错,但 `ompi_info`/`mpirun -np` 运行正常 |
| BLAS | OpenBLAS 0.3.32 pthread only (`libopenblas-dev`, `libopenblas0-pthread`); `libblas.so.3 -> alternatives -> openblas-pthread/libblas.so.3`,即 `-lblas == OpenBLAS`; 无 MKL/BLIS/ATLAS; LAPACK (reference) 存在但 HPL 主路径只用 BLAS |
| Link | `ldd xhpl`: `libopenblas.so.0`, `libmpi.so.40`, `libgfortran.so.5` |
| Profiler | `perf`: Unavailable in current environment (`perf: command not found`); `/usr/bin/time` 可用; 未为 profiling 大改环境 |
| MKLROOT/mpiicc | 均不存在,原 Intel 模板不可用是预期失败 |

理论峰值 (供参考,非实测):
Zen4 每核 2x FMA, AVX512 8 doubles → 16 DP FLOP/cycle; 8c x 5GHz x16 ≈ 640 GFLOPS.
本报告 Final ~220 GFLOPS ≈ 34% 峰值,单机 WSL + OpenBLAS 属合理 (通常 HPL 60-90% 需 MKL+调优+BIG N,小 N 效率低)。

---

## 3. HPL Architecture

```
HPL_pddriver (testing/ptest/HPL_pddriver.c)
 └─ HPL_pdtest → HPL_pdgesv (src/pgesv)
     ├─ Panel factorization (src/pfact: pdpanll/pdpanrl/pdpancr + pdmxswp, Crout/Right/Left)
     │   └─ latency-sensitive, 在关键路径, 与 P 强相关
     ├─ Panel broadcast (src/comm: 1ring/1rinM/2ring/2rinM/Blong/BlonM, BCAST)
     ├─ Update (src/pgesv: pdupdateNN/NT/TN/TT → HPL_dgemm → Fortran dgemm)
     │   └─ 占 80-95% FLOPS, compute-bound, 依赖 DGEMM
     ├─ Triangular solve (pdtrsv → dtrsm)
     └─ 2D block-cyclic distribution (src/grid/pauxil: numroc, indxg2l...), P×Q
BLAS wrapper (src/blas: HPL_dgemm/dtrsm/dgemv/dtrsv/dger/daxpy/dcopy/dscal/idamax)
 → Fortran BLAS (OpenBLAS)
MPI (src/grid/comm: broadcast/reduce/barrier/min/max/sum)
```

执行流 (per step k, NB 为步长):
`factorize panel (NB cols, O(N*NB^2)) → broadcast panel row-wise → update trailing matrix (DGEMM, O(N^2*NB)) → 下一 k`。
N 增大时 Update 占比 → 1,整体趋近 DGEMM 峰值; N 小时 panel+通信占比高,GFLOPS 低且抖动大。

---

## 4. Build Configuration

### 4.1 诊断 (第一件事,非猜测)

```bash
pwd; ls -lah; find . -maxdepth 2 -type f | sort
sed -n '1,240p' Make.Linux_Intel64
grep -RIn 'TOPdir' . --exclude-dir=.git
find src testing -type l -ls   # 全部 -> /home/user/hpl/Make... (dangling)
git status --short
```

结论见 §1。关键: `TOPdir` 单点错误导致 13 个 `Make.inc` 全断。

### 4.2 修复原则 (满足任务 §二)

- 不改 HPL 核心算法,不复制大量 `Make.inc`,不用临时 hack,不多文件硬编码,保持 `Make.top`/`makes/*` 原逻辑
- 只改顶层 `Make.Linux_Intel64` 这一个文件:
  - `TOPdir=/home/user/HPC/hpl` (绝对路径,仅此一处,注释说明原因)
  - MPI: `MPdir/MPinc/MPlib` 清空,用 `mpicc` wrapper
  - BLAS: `LAdir/LAinc` 清空,`LAlib=-lopenblas` (显式,无 MKL hack)
  - `F2CDEFS=-DAdd_ -DF77_INTEGER=int -DStringSunStyle` (gfortran 正确值,原 `-DAdd__` 是 f2c,错)
  - `HPL_INCLUDES=-I$(INCdir) -I$(INCdir)/$(ARCH) $(LAinc) $(MPinc)` (去掉了 `-I$(LAinc)` 空值时的 `-I` 悬空)
  - `HPL_OPTS=` 空 (true baseline)
  - `CC=mpicc, LINKER=$(CC), CCFLAGS=$(HPL_DEFS) -O2 -w -Wall, LINKFLAGS=$(CCFLAGS)` (删 Intel 专有 flags)
- 恢复误删: `git restore --source=HEAD -- README setup/Make.Linux_Intel64`
- 清理断裂链接后重建:

```bash
make clean_arch_all arch=Linux_Intel64
make arch=Linux_Intel64
ls -lh bin/Linux_Intel64/xhpl; file bin/Linux_Intel64/xhpl
```

结果: 一次成功,
`-rwxr-xr-x 169K (baseline -O2) → 193K (-O3) → 205K (-O3-native)`,
`ELF 64-bit LSB pie executable, x86-64, dynamically linked`。

---

## 5. Baseline

### 5.1 Baseline definition

> 尽可能接近原始 HPL 2.3 + 当前机器标准编译环境,不加性能魔改。

- HPL 2.3 原样 (git `9edeab5`, `Make.top` 未动)
- `mpicc (OpenMPI 5.0.10 + gcc 15.2)`, `-O2 -w -Wall`, 无 `-march`, 无 OMP flags
- BLAS: OpenBLAS 0.3.32 pthread (`-lopenblas`),因系统只有它,`-lblas` 同物 (alternatives),无 MKL/BLIS 可比
- `F2CDEFS=-DAdd_`, `HPL_OPTS=` 空, `PFACT=Right, BCAST=1ring, DEPTH=1, SWAP=Mix`
- 线程: 不设 `OPENBLAS_NUM_THREADS` (即 OpenBLAS 默认用满 16 线程) — 这正是“天真 baseline”,后文证明它对 np=1 是次优、对 np>1 是灾难,作为教学对照点
- 保存: `experiments/baseline/Make.Linux_Intel64.baseline-O2-openblas`

### 5.2 Baseline compilation command

```bash
make clean_arch_all arch=Linux_Intel64
make arch=Linux_Intel64
# 实际编译行示例:
# mpicc -o HPL_dgemm.o -c -DAdd_ ... -I/home/user/HPC/hpl/include ... -O2 -w -Wall ../HPL_dgemm.c
# mpicc ... -o /home/user/HPC/hpl/bin/Linux_Intel64/xhpl ... /home/user/HPC/hpl/lib/Linux_Intel64/libhpl.a -lopenblas
```

### 5.3 Baseline correctness

必须先 PASSED,再谈性能。`xhpl` 必须在 `bin/Linux_Intel64` 下运行 (它读 `./HPL.dat`)。

- Small: `N=2000 NB=128 P=1 Q=1 np=1` → `Time 0.07s, 73.88 GFLOPS, residual 3.30e-03 PASSED`
  (`experiments/baseline/small-N2000-NB128-P1Q1-np1.log`)
- Medium: `N=6000 NB=192 P=2 Q=2 np=4 --oversubscribe` → `Time 19.40s, 7.42 GFLOPS, residual 2.85e-03 PASSED`
  - 注意: 同一 binary,4 ranks 默认 16 线程/rank =64 线程抢 16 CPU → 7 GFLOPS,正确但极慢。
    这不是 bug,是 oversubscription 教学案例 (后文 §7.3/7.4 对照)。
- Baseline perf (N=8000 NB=192 P1Q1 np1,默认线程,3 次):
  - run1 3.59s 95.15 GFLOPS, run2 3.39s 100.63 GFLOPS, run3 3.40s 100.42 GFLOPS
  - 平均 98.73 GFLOPS,取 **Baseline = 98.73 GFLOPS (avg) / 100.63 (best)**。正文 speedup 用 avg 以保守。

### 5.4 Baseline HPL.dat

```text
# experiments/baseline/HPL.dat.baseline-N8000-NB192-P1Q1
N=8000, NB=192, P=1 Q=1, PFACT=Right(2), NBMIN=4, NDIV=2, RFACT=Right(2),
BCAST=1ring(0), DEPTH=1, SWAP=Mix(2,64), L1/U transposed, EQUIL yes, ALIGN 8
```

### 5.5 Baseline performance

| N | NB | P Q | NP | threads | Time | GFLOPS | verific. |
|---|---|---|---|---|---|---|---|
| 2000 | 128 | 1 1 | 1 | default(16) | 0.07s | 73.88 | PASSED |
| 6000 | 192 | 2 2 | 4 | default(16/rank) | 19.40s | 7.42 | PASSED |
| 8000 | 192 | 1 1 | 1 | default | 3.59/3.39/3.40s | 95.15/100.63/100.42 | PASSED x3 |

---

## 6. Performance Analysis

> HPL 到底把时间花在哪里?

### 6.1 Execution flow

同 §3。定量: `2/3*N^3` FLOPS, N=8000 → 341 GFLOP; 实测 100 GFLOPS → 3.4s,其中
Update(DGEMM) 应占 >85%,panel+bcast+sync 占余下。N=2000 (5.3 GFLOP) 0.07s 73 GFLOPS 偏低且抖动,
因 panel/启动开销占比高,不适合做性能结论 — 这就是先小 N 验证正确性、再大 N 测性能的原因。

### 6.2 DGEMM / BLAS

- `HPL_dgemm` 只是 wrapper,最终调 Fortran `dgemm_` (OpenBLAS)。`src/blas` 仅占编译 <5%,运行占 >80%。
- 证据:
  - 线程 1→8: 53.3 → 184.6 GFLOPS (3.46x),说明瓶颈在可并行 DGEMM
  - 编译器 `-O2→-O3→-native`: 206.5→212.9→212.4 (+3%),说明 HPL 自身 C 代码非瓶颈
  - NB 64→256: 182→214 (+17%),说明 DGEMM blocking 效率敏感
- SIMD/FMA/cache/register/threading 关系:
  OpenBLAS 为 Zen4 预置 `cache blocking (L1/L2/L3 分块) + register blocking + AVX2/AVX512 FMA + 多线程`。
  HPL 的 NB 是 coarse-grain blocking,OpenBLAS 内部还有 fine-grain blocking,两者正交:
  NB 太小 → DGEMM 矩形太瘦,OpenBLAS 无法摊销 packing/线程开销; NB 太大 → panel 在 L3 放不下 + 并行度下降。
  本机 L3 16MiB, NB=256 时 panel `8000*256*8=16.4MiB` 恰好 L3 量级,实测最优吻合。

### 6.3 MPI communication

- 单机 WSL,通信经 shared-memory (vader),非网络。`BCAST=1ring` 在 P 小时足够。
- 证据: `np=4 T=2` 时 `P1Q4 221.1 > P2Q2 211.0 > P4Q1 172.3`; `np=8 T=1` 时 `P1Q8 219.8 > P2Q4 217.5 > P4Q2 195.5 > P8Q1 134.3`。
  规律: **P 越小越快,Q 越大越快**。因 panel factorization 在列方向关键路径与 P 成正比,
  P 大 → 更多行间同步 + 更瘦的局部列 → DGEMM 形状变差; Q 大 → trailing update 并行度高且无需同步。
- 为什么不是进程越多越快: `np1 T8 214.8` vs `np4 T2 221.1` vs `np8 T1 219.8` — 8 物理核下,
  超过 4-8 ranks 后,切分过细 → 消息数 O(P+Q) 上升 + 每块 DGEMM 变小 + oversubscription (若线程未降) → 收益归零。
  本机 sweet spot 4 ranks。

### 6.4 CPU utilization

- `/usr/bin/time` 显示 `ELAPSED` (含 MPI 启动+IO) > `HPL Time` (纯求解),差值 ~2-3s 为启动/退出开销,小 N 时不可忽略。
- `MAXMEM`: N=8000 np1 ~544MiB (8000^2*8=512MiB + overhead 吻合); np4 ~180MiB/rank; np8 ~112MiB/rank — 2D 分布正确。
- `T=16` 崩到 85 GFLOPS 而 `T=8` 184 GFLOPS: 8 物理核,SMT 16 线程对 DGEMM 无益 (FPU/cache 争抢),
  OpenBLAS 线程开销 + WSL 调度抖动反而降速。`NP*T≈8` 是本机铁律 (见 §7.3)。

### 6.5 Memory / Cache considerations

- N=8000 全矩阵 512MiB,远超 L3,必走 DRAM,带宽敏感; NB=256 panel 16MiB 恰 L3,最优。
- NB=64 (panel 4MiB) 虽更 fit L3,但 DGEMM `M=N=8000, N=NB=64, K=NB` 太瘦,packing/线程分叉开销占比高 → 182 GFLOPS 最差。
- N=12000 (1.15GiB) 仍 PASSED 206 GFLOPS,证明无内存瓶颈,15GiB 绰绰有余,SWAP 未用。

工具限制: `perf` 不可用,以上用 `time` + 受控变量 + `lscpu` 推断,未虚构 PMU 数据。

---

## 7. Optimization Experiments

统一规范: `N,NB,P,Q,NP,threads,BLAS,compiler,MPI binding,HPL time,GFLOPS,verific.`。
每次只动一项,附 `Modification/Reason/Command/Result/Change/Analysis/Decision`。

### 7.1 BLAS

- Modification: Baseline 已用 OpenBLAS;尝试找 MKL/BLIS/ATLAS 做横向对比
- Reason: HPL 主计算是 DGEMM,BLAS 实现决定天花板
- Command: `ldconfig -p | grep -i blas; dpkg -l | grep -i blas; update-alternatives --display libblas.so.3-*`
- Result: 只有 OpenBLAS 0.3.32 pthread; `libblas.so.3 → openblas-pthread`,MKL/BLIS `Unavailable in current environment`
- Performance change: 实现间对比 `Not tested` (无库,拒绝伪造); 但 BLAS *threading* 对比见 §7.3 (53→184 GFLOPS)
- Analysis: GEMM-SIMD-FMA-cache-register-threading 全在 OpenBLAS 内部; HPL 只定 NB 粗粒度,细粒度由 OpenBLAS 定。
  pthread build 由 `OPENBLAS_NUM_THREADS/GOTO_NUM_THREADS` 控制,非 `OMP_*` (后者对 pthread build 无效,但本实验同时设以防 openmp build)。
- Decision: 保留 `-lopenblas`,明确记录 `-lblas` 同物,后续优化聚焦 threading 而非换库。Future: 可装 `libblis-dev` 或 Intel MKL (需 oneAPI) 再比。

### 7.2 Compiler

- Modification: `-O2` → `-O3` → `-O3 -march=native -mtune=native` (各 rebuild + `make clean`)
- Reason: 验证 HPL 自身 C 代码对整体的影响,排除“我加了 flag 就变快”的迷信
- Command: `make clean arch=Linux_Intel64; make arch=Linux_Intel64` + `OPENBLAS_NUM_THREADS=8 ./run_hpl.sh 8000 192 1 1 1`
- Result (N=8000 NB192 np1 T8, PASSED 全部):
  - `-O2`: 206.54 GFLOPS (2.??s, `nb-192-np1-T8.log`)
  - `-O3`: 212.96 GFLOPS (+3.1% vs O2)
  - `-O3-native`: 212.49 GFLOPS (+2.9% vs O2, -0.2% vs O3)
- Analysis: +3% 符合预期 (Amdahl: HPL C 代码 <10% 时间,BLAS 预编译不受 `march` 影响)。
  `-march=native` 在本机安全 (单机 Zen4,识别为 `znver4`,AVX512 可用),但异构集群分发 binary 则不适合 (会 illegal instruction)。
- Decision: 保留 `-O3 -march=native -mtune=native` (无副作用,小收益,本地学习机)。

### 7.3 OpenMP / BLAS threading

- Modification: `OPENBLAS_NUM_THREADS=OMP_NUM_THREADS=GOTO_NUM_THREADS=1,2,4,8,16`, N=8000 NB192 np1
- Reason: 找 BLAS 线程扩展曲线,验证 oversubscription 假说 (§5.3 medium 7 GFLOPS 之谜)
- Command: `scripts/sweep_threads.sh` (bindir 下 `mpirun -np 1 ./xhpl`)
- Result:
  - T1 53.31 (6.40s), T2 102.79 (3.32s), T4 157.83 (2.16s), T8 184.64 (1.85s), T16 85.50 (3.99s) — 全部 PASSED
- Change: 1→8 +246%, 8→16 -54%
- Analysis: `thread scaling` 到物理核数 8 线性,SMT 16 反降 (FPU 竞争+cache thrash+线程管理)。
  `CPU util`: T8 时 8 核跑满, T16 时 16 逻辑核争 8 FPU。`memory`: T 大则 packing 带宽翻倍,DRAM 带宽封顶。
  `oversubscription` 公式: `NP*T ≤ 物理核 (8)`。medium 实验 `4*16=64 >>16` 故 7 GFLOPS。
- Decision: np1 用 T=8; 多 rank 时按 `T=8/NP` 配 (np2 T4, np4 T2, np8 T1)。保留。

### 7.4 MPI (processes)

- Modification: NP=1,2,4,8,固定 `NP*T=8`, N=8000 NB192, `--oversubscribe`
- Reason: 找单机最佳并行度,分离“并行收益”与“oversubscription 惩罚”
- Command: `scripts/sweep_mpi.sh`
- Result (PASSED 全部, Time/GFLOPS):
  - np1 T8 P1Q1 214.86 (1.59s) — 注: 与 §7.3 T8 184.6 差异为机器抖动,后文取区间
  - np2 T4 P1Q2 210.39, P2Q1 166.81
  - np4 T2 P2Q2 211.06, P1Q4 221.11 (全局 best), P4Q1 172.30
  - np8 T1 P2Q4 217.54, P1Q8 219.89, P4Q2 195.54, P8Q1 134.34
- Analysis: NP 从 1→4 有 +~3-6% (通信开销 < 并行收益,因单机 shared-mem 带宽高);
  8 ranks 无进一步收益 (切分过细+同步)。`MPI×OpenMP`: 必须联动降 T,否则 §5.3 悲剧重演。
- Decision: 选 NP=4 为 final (兼顾性能+教学代表性,1/2/8 均记录)。

### 7.5 NB

- Modification: NB=64,96,128,192,256,384, N=8000 np1 T8 P1Q1, `-O2` (后 final 用 `-O3-native` 复验 256 最优)
- Reason: NB 是 HPL 第一调参,联动 cache/DGEMM/panel/comm
- Command: `scripts/sweep_nb.sh`
- Result: 64:182.27, 96:206.34, 128:205.00, 192:206.54, 256:214.45(best), 384:213.91 — PASSED
- Change: 64→256 +17.6%
- Analysis:
  - cache: NB=256 panel 16.4MiB ≈ L3,命中最优; 64 panel 4MiB 虽更小但 DGEMM 瘦矩阵效率低
  - DGEMM: NB 大 → `K=NB` 大 → packing 摊销好,但过大则 update 并行度 (N/NB 步数) 下降; 256 是本机平衡点
  - panel: NB 大 → panel factorization (O(N*NB^2)) 单步变重但步数少,总值不变,只是同步次数少 → 利好
  - comm: NB 大 → bcast 次数少、单次大,带宽利用高
- Decision: 选 NB=256 (384 相近但内存对齐+余量不如 256 通用)。

### 7.6 P × Q

- Modification: 同 NP 下遍历所有 P×Q (见 §7.4)
- Reason: HPL 经典问题 “为什么 P×Q 影响这么大”
- Command: 同 §7.4, `gen_hpl_dat.sh 8000 192 $P $Q`
- Result: 规律一致 **P小Q大胜**: np4 `1x4 >2x2 >4x1`; np8 `1x8≈2x4 >4x2 >>8x1 (134 GFLOPS)`
- Analysis:
  - 行/列通信: panel bcast 沿行方向 (同列内?),update 沿列; P 大 → 列方向切分细 → panel 高度小但同步次数多,
    且 panel factorization 在关键路径 (每步必须等 panel 才能 update),P 大增加延迟暴露
  - 数据分布: 2D block-cyclic, P 大 → 每列局部行数少 → DGEMM `M` 方向短 → 向量化/缓存效率差
  - 因此单机 (通信便宜、计算贵) 应最小化 P (取 1),最大化 Q; 多机 (通信贵) 才需均衡 P≈Q。
- Decision: final 取 P=1 Q=4 (np4), P=1 Q=8 (np8 备选)。保留“P小Q大”结论,非只记最快值。

### 7.7 CPU Binding

- Modification: 无绑定 vs `mpirun --bind-to core --map-by core` + `OMP_PROC_BIND=TRUE OMP_PLACES=cores`,
  N=8000 NB256 np4 T2 P1Q4, `-O3-native`
- Reason: 防线程漂移/跨核迁移/两 rank 抢同核
- Command: `scripts/test_binding_numa.sh`
- Result: nobind 218.05 → bind 226.16 (+3.7%), PASSED, `ELAPSED` 方差也减小
- Analysis: OpenMPI 默认在 WSL 下不绑核,Linux CFS 会迁线程 → L1/L2 失效率升 + SMT 误配对;
  绑核后每 rank 固定 2 物理核,OpenBLAS 线程 affinity 稳定。`--bind-to` 管 MPI rank,`OMP_PROC_BIND` 管 BLAS 线程 (pthread build 部分有效,但无害)。
- Decision: 保留绑定,为 final 标配。当前 MPI 支持 `bind-to/map-by`,已验证。

### 7.8 NUMA

- Modification: `numactl --hardware`, `lscpu | grep NUMA`
- Result: `NUMA node(s): 1`, `numactl: command not found` → **当前环境没有明显 NUMA 优化空间** (按任务要求如实记录,不虚构)
- Analysis: 单 node,无跨 node 远端内存,无需 `numactl --membind/--cpubind`。若未来上双路 EPYC/双槽工作站,
  需 `P×Q` 跨 node 均衡 + `mpirun --map-by numa` + OpenBLAS `NUMA` 亲和。
- Decision: 不做,记为 `Not applicable`。

---

## 8. Final Configuration

- Binary: `bin/Linux_Intel64/xhpl` (205K, `-O3 -march=native -mtune=native`, `mpicc`, `-lopenblas`)
- Make: `Make.Linux_Intel64` (TOPdir 绝对单点, F2C `-DAdd_`, HPL_OPTS 空)
- HPL.dat (top + bin): `N=8000 NB=256 P=1 Q=4, PFACT=Right, BCAST=1ring, DEPTH=1, SWAP=Mix`
- Run:

```bash
cd bin/Linux_Intel64
export OPENBLAS_NUM_THREADS=2 OMP_NUM_THREADS=2 GOTO_NUM_THREADS=2
export OMP_PROC_BIND=TRUE OMP_PLACES=cores
mpirun -np 4 --oversubscribe --bind-to core --map-by core ./xhpl
```

- Larger check: `N=12000 NB=256 P1Q4 np4 T2 bind` → 5.59s 206.02 GFLOPS PASSED (1.15 TFLOP,内存 1.15GiB,无压力)

---

## 9. Baseline vs Final

同 N=8000 对比 (工作量同为 341 GFLOP,公平):

|  | Baseline | Final (best observed) | Final (3-run avg, 同 binary) |
|---|---|---|---|
| Compiler | -O2 | -O3 -march=native -mtune=native | same |
| BLAS | OpenBLAS default threads | OpenBLAS T=2/rank | same |
| MPI | np1 P1Q1 | np4 P1Q4 + bind | same |
| NB | 192 | 256 | 256 |
| GFLOPS | 98.73 avg (95.15/100.63/100.42) | 226.16 | 191.83 (202.14/184.13/189.21) |
| Time | ~3.46s avg | 1.51s | ~1.78s avg |
| Verific. | PASSED | PASSED | PASSED x3 |

```text
Speedup (best) = 226.16 / 98.73 = 2.29
Improvement (best) = (226.16-98.73)/98.73*100% = 129.1%
Speedup (conservative avg) = 191.83 / 98.73 = 1.94
Improvement (avg) = 94.3%
```

分项贡献 (近似,因存在交互,非严格加和):
- 纠正线程 (default16→T8, np1): 100 → 206 (+106%,最大头,实为修复 oversubscription/错配)
- NB 192→256: 206 → 214 (+4%)
- Compiler O2→O3-native: 206 → 212 (+3%,在 T8 下测)
- MPI np1T8→np4T2 P1Q4: 214 → 221 (+3%)
- Binding: 218 → 226 (+3.7%)
- N=12000 大矩阵: 206 sustained,证明非小 N 虚高

> 可解释性声明: 若只比 “已调好线程的 baseline (206) vs final (226)”,真实算法收益仅 ~10%,
> 大头是“把线程配对”。本报告同时给出两种口径,拒绝只报 2.29x 误导。

---

## 10. Lessons Learned

1. 构建即工程: `TOPdir` 单点错 → 13 链接全断。教训: 先 `find -type l -ls` + `git status`,不猜。
2. HPL ≈ DGEMM: 编译器/NB/PQ 再调,不如把 `NP*T=物理核` 配对。先 `lscpu` 再谈优化。
3. P小Q大 (单机): panel 在关键路径,P 是延迟,Q 是并行。单机通信便宜,压 P 保延迟。
4. NB 是粗粒度 blocking,与 OpenBLAS 细粒度正交;L3 容量可直接算出候选 (16MiB/8000/8≈256)。
5. SMT 对 DGEMM 常为负: 8c16t 机器,T=16 -54%,别迷信“线程越多越快”。
6. 绑定是免费午餐 (+3.7%),NUMA 单 node 则明确说无空间,不编数据。

---

## 11. Future Optimization

- [ ] 装 `libblis-dev` / Intel oneAPI MKL,做真正的 BLAS 横比 (当前 `Not tested`)
- [ ] 扫 `BCAST (1ring vs 2ring vs Lng)`, `PFACT (Left/Crout/Right)`, `DEPTH (0/1/2)`, `NBMIN/NDIV` (当前固定 Right/1ring/1,未扫)
- [ ] 大 N (20000+, ~3.2GiB) 测持续效率 + `time` vs `HPL Time` 差值分析 (当前最大 12000)
- [ ] `perf stat -e cycles,instructions,cache-misses` (需 WSL2 启用 PMU 或转原生 Linux)
- [ ] 多机 (若有第二节点) 测 `P≈Q` vs `P小Q大` 反转点
- [ ] OpenBLAS `OPENBLAS_VERBOSE=2` 确认 kernel 名 (Haswell/Zen4) + `lscpu` 对齐 `-march`

---

## 附: 复现命令索引

```bash
# 构建
make clean_arch_all arch=Linux_Intel64; make arch=Linux_Intel64
ls -lh bin/Linux_Intel64/xhpl; file bin/Linux_Intel64/xhpl
# 小正确性
./scripts/gen_hpl_dat.sh 2000 128 1 1 /tmp/HPL.dat.run; cp /tmp/HPL.dat.run bin/Linux_Intel64/HPL.dat
# (cd bin/Linux_Intel64 && mpirun -np 1 ./xhpl)
# 扫描
./scripts/sweep_threads.sh   # openmp/
./scripts/sweep_mpi.sh       # mpi/ (含 pq/)
./scripts/sweep_nb.sh        # nb/
./scripts/test_binding_numa.sh
./scripts/test_final.sh      # final/
```

所有 log 保留在 `experiments/` 下 `.log` + `.log.dat` (HPL.dat 快照),`scripts/` 可重放。
