#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
# MPI scaling: keep total threads ~8 (physical cores)
# N=8000 NB=192
run_case() {
  NP=$1; T=$2; P=$3; Q=$4
  export OPENBLAS_NUM_THREADS=$T OMP_NUM_THREADS=$T GOTO_NUM_THREADS=$T
  LOG=/home/user/HPC/hpl/experiments/mpi/mpi-np${NP}-T${T}-P${P}Q${Q}.log
  echo "===== MPI NP=$NP T=$T P=$P Q=$Q ====="
  /home/user/HPC/hpl/scripts/run_hpl.sh 8000 192 $P $Q $NP $LOG 2>&1 | grep -E 'RUN N=|WR10|PASSED|FAILED|ELAPSED'
}
run_case 1 8 1 1
run_case 2 4 1 2
run_case 2 4 2 1
run_case 4 2 2 2
run_case 4 2 1 4
run_case 4 2 4 1
run_case 8 1 2 4
run_case 8 1 4 2
run_case 8 1 1 8
run_case 8 1 8 1
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS
