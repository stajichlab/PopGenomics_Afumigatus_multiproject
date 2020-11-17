#!/usr/bin/bash
#SBATCH -p short -N 1 -n 8 --mem 24gb --out logs/assemble_unmapped.%a.log

module load SPAdes/3.14.1
module load samtools
module load BBMap

MEM=24
FASTQEXT=fastq
UNMAPPEDASM=unmapped_asm
UNMAPPED=unmapped
if [ -f config.txt ]; then
  source config.txt
fi
mkdir -p $UNMAPPED $UNMAPPEDASM

CPU=2
if [ $SLURM_CPUS_ON_NODE ]; then
  CPU=$SLURM_CPUS_ON_NODE
fi
N=${SLURM_ARRAY_TASK_ID}
if [ -z $N ]; then
  N=$1
fi
if [ -z $N ]; then
  echo "cannot run without a number provided either cmdline or --array in sbatch"
  exit
fi


MAX=$(wc -l $SAMPLESINFO | awk '{print $1}')
if [ $N -gt $MAX ]; then
  echo "$N is too big, only $MAX lines in $SAMPLESINFO"
  exit
fi

IFS=,
tail -n +2 $SAMPLESINFO | sed -n ${N}p | while read STRAIN FILEBASE
do
  FINALFILE=$ALNFOLDER/$STRAIN.$HTCEXT
  UMAP=$UNMAPPED/${STRAIN}.$FASTQEXT
  UMAPSINGLE=$UNMAPPED/${STRAIN}_single.$FASTQEXT
  if [ ! -f $UMAP ]; then
    samtools fastq -f 4 --threads $CPU -N -s $UMAPSINGLE -o $UMAP $FINALFILE
    pigz -f $UMAPSINGLE
    repair.sh in=$UMAP out=$UMAP.gz overwrite=true
    unlink $UMAP
  fi
  if [[ ! -f $UMAP.gz && ! -f $UMAPSINGLE.gz ]]; then
    echo "Need unmapped FASTQ file, skipping $STRAIN ($FILEBASE) ($UMAP $UMAPSINGLE)"
  else
    spades.py --pe-12 1 $UMAP.gz --pe-s 1 $UMAPSINGLE.gz -o $UNMAPPEDASM/$STRAIN -t $CPU -m $MEM --careful
  fi
done
