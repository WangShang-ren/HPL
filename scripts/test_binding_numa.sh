#!/bin/bash
set -u
cd /home/user/HPC/hpl/bin/Linux_Intel64
/home/user/HPC/hpl/scripts/gen_hpl_dat.sh 8000 256 1 4 /tmp/HPL.dat.run >/dev/null
cp /tmp/HPL.dat.run ./HPL.dat
cp /tmp/HPL.dat.run /home/user/HPC/hpl/experiments/final/HPL.dat.final-candidate.dat
echo "===== BIND TEST 1: no binding ====="
export OPENBLAS_NUM_THREADS=2 OMP_NUM_THREADS=2 GOTO_NUM_THREADS=2
unset OMP_PROC_BIND OMP_PLACES
mpirun -np 4 --oversubscribe ./xhpl 2>&1 | grep -E 'WR10|PASSED' | tee /home/user/HPC/hpl/experiments/mpi/binding-nobind.log
echo "===== BIND TEST 2: OMP_PROC_BIND=TRUE + mpirun bind-to core ====="
export OMP_PROC_BIND=TRUE OMP_PLACES=cores
mpirun -np 4 --oversubscribe --bind-to core --map-by core ./xhpl 2>&1 | grep -E 'WR10|PASSED' | tee /home/user/HPC/hpl/experiments/mpi/binding-bind.log
echo "===== NUMA CHECK ====="
numactl --hardware 2>&1 | tee /home/user/HPC/hpl/experiments/mpi/numa-check.log
lscpu | grep -i numa | tee -a /home/user/HPC/hpl/experiments/mpi/numa-check.log
unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS GOTO_NUM_THREADS OMP_PROC_BIND OMP_PLACES
