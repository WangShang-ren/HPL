# experiments/ 索引

- baseline/: 保守 -O2 + OpenBLAS 默认线程, N=8000 3次 (95-100 GFLOPS) + small/medium PASSED
- openmp/: T=1,2,4,8,16 (np1 N=8000 NB192): 53/102/157/184/85 GFLOPS, T=8最优, T=16崩
- mpi/: NP=1,2,4,8 且 NP*T=8, 全部PASSED; best np4-T2-P1Q4 221.11 GFLOPS; binding-nobind/bind 对比
- nb/: NB=64,96,128,192,256,384 (np1 T8): 182/206/205/206/214/213, NB=256最优
- pq/: 见 mpi/ (P小Q大规律: P1Q4>P2Q2>P4Q1; P1Q8>P2Q4>P4Q2>P8Q1), 本目录为快捷方式说明
- compiler/: -O2(206.54) vs -O3(212.96,+3.1%) vs -O3-native(212.49,+2.9%), Make.O3/Make.O3-native存档
- blas/: 只有OpenBLAS 0.3.32可用, MKL/BLIS Unavailable, -lblas经alternatives同物; threading收益见openmp/
- final/: 最终 -O3-native + NB256 + np4-T2-P1Q4 + bind, N=8000 3次 + N=12000 206 GFLOPS PASSED

复现: scripts/sweep_*.sh, scripts/test_*.sh
