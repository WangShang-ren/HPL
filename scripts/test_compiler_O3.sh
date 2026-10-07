#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
export OPENBLAS_NUM_THREADS=8 OMP_NUM_THREADS=8 GOTO_NUM_THREADS=8
LOG=/home/user/HPC/hpl/experiments/compiler/compiler-O3-N8000-NB192-np1-T8.log
echo "===== COMPILER O3 ====="
/home/user/HPC/hpl/scripts/run_hpl.sh 8000 192 1 1 1 $LOG 2>&1 | grep -E 'RUN N=|WR10|PASSED|FAILED|ELAPSED'
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS
