#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
for T in 1 2 4 8 16; do
  echo "===== THREAD_TEST T=$T ====="
  export OPENBLAS_NUM_THREADS=$T
  export OMP_NUM_THREADS=$T
  export GOTO_NUM_THREADS=$T
  /home/user/HPC/hpl/scripts/run_hpl.sh 8000 192 1 1 1 /home/user/HPC/hpl/experiments/openmp/thread-np1-T${T}.log 2>&1 | grep -E 'RUN N=|WR10|PASSED|FAILED|ELAPSED'
done
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS
