#!/bin/bash
# run_hpl.sh N NB P Q NP EXTRA_ENV LOGFILE
# Example: ./run_hpl.sh 8000 192 1 1 1 "" log.txt
set -u
N=$1; NB=$2; P=$3; Q=$4; NP=$5
LOG=${6:-/tmp/hpl.log}
HPLDIR=/home/user/HPC/hpl
BINDIR=$HPLDIR/bin/Linux_Intel64
TMPDAT=/tmp/HPL.dat.run
$HPLDIR/scripts/gen_hpl_dat.sh $N $NB $P $Q $TMPDAT >/dev/null
cp $TMPDAT $BINDIR/HPL.dat
cp $TMPDAT ${LOG}.dat
echo "=== RUN N=$N NB=$NB P=$P Q=$Q NP=$NP LOG=$LOG ===" | tee "$LOG"
echo "CMD: mpirun -np $NP --oversubscribe ./xhpl" | tee -a "$LOG"
echo "ENV: OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS:-unset} OMP_NUM_THREADS=${OMP_NUM_THREADS:-unset} OMP_PROC_BIND=${OMP_PROC_BIND:-unset} OMP_PLACES=${OMP_PLACES:-unset}" | tee -a "$LOG"
/usr/bin/time -f "ELAPSED=%e MAXMEM=%MKB" mpirun -np $NP --oversubscribe ./xhpl 2>&1 | tee -a "$LOG"
echo "=== DONE ===" | tee -a "$LOG"
