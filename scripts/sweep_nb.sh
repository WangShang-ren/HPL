#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
export OPENBLAS_NUM_THREADS=8 OMP_NUM_THREADS=8 GOTO_NUM_THREADS=8
for NB in 64 96 128 192 256 384; do
  LOG=/home/user/HPC/hpl/experiments/nb/nb-${NB}-np1-T8.log
  echo "===== NB=$NB ====="
  /home/user/HPC/hpl/scripts/run_hpl.sh 8000 $NB 1 1 1 $LOG 2>&1 | grep -E 'RUN N=|WR10|PASSED|FAILED|ELAPSED'
done
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS
