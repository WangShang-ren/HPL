#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
export OPENBLAS_NUM_THREADS=2 OMP_NUM_THREADS=2 GOTO_NUM_THREADS=2
export OMP_PROC_BIND=TRUE OMP_PLACES=cores
for i in 1 2 3; do
  /home/user/HPC/hpl/scripts/gen_hpl_dat.sh 8000 256 1 4 /tmp/HPL.dat.run >/dev/null
  cp /tmp/HPL.dat.run ./HPL.dat
  LOG=/home/user/HPC/hpl/experiments/final/final-N8000-NB256-P1Q4-np4-T2-bind-run${i}.log
  echo "===== FINAL RUN $i =====" | tee $LOG
  echo "ENV OPENBLAS_NUM_THREADS=2 OMP_PROC_BIND=TRUE" | tee -a $LOG
  mpirun -np 4 --oversubscribe --bind-to core --map-by core ./xhpl 2>&1 | tee -a $LOG | grep -E 'WR10|PASSED|FAILED'
done
# Larger N demonstration
/home/user/HPC/hpl/scripts/gen_hpl_dat.sh 12000 256 1 4 /tmp/HPL.dat.run >/dev/null
cp /tmp/HPL.dat.run ./HPL.dat
cp /tmp/HPL.dat.run /home/user/HPC/hpl/experiments/final/HPL.dat.final-N12000.dat
LOG=/home/user/HPC/hpl/experiments/final/final-N12000-NB256-P1Q4-np4-T2-bind.log
echo "===== FINAL LARGE N=12000 =====" | tee $LOG
timeout 300 mpirun -np 4 --oversubscribe --bind-to core --map-by core ./xhpl 2>&1 | tee -a $LOG | grep -E 'WR10|PASSED|FAILED'
# restore final candidate dat for default run
cp /home/user/HPC/hpl/experiments/final/HPL.dat.final-candidate.dat ./HPL.dat 2>/dev/null || true
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS OMP_PROC_BIND OMP_PLACES
