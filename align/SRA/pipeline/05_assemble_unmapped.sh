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
tail -n +2 $SAMPLESINFO | cut -d, -f2 | sort | uniq | sed -n ${N}p | while read STRAIN
do
  # BEGIN THIS PART IS PROJECT SPECIFIC LIKELY
  # END THIS PART IS PROJECT SPECIFIC LIKELY
  STRAIN=$(echo $STRAIN | perl -p -e 's/[\/ ]/_/g')
  echo "STRAIN is $STRAIN"

  UMAP=$UNMAPPED/${STRAIN}.$FASTQEXT
  UMAPSINGLE=$UNMAPPED/${STRAIN}_single.$FASTQEXT

  if [ ! -z $FORCE ]; then
    rm -f $UMAP $UMAPSINGLE $UMAP.gz $UMAPSINGLE.gz
  fi
  if [ ! -f $UMAP.gz ]; then
    TMP=tmp
    mkdir -p $TMP
    for ALNFILE in $(ls $ALNFOLDER/$STRAIN.*.$HTCEXT)
    do
      BASE=$(basename $ALNFILE .$HTCEXT)
      TMPSING=$TMP/$BASE.single.$FASTQEXT
      TMPPAIR=$TMP/$BASE.pair.$FASTQEXT
      samtools fastq -f 4 --threads $CPU -N -s $TMPSING -o $TMPPAIR $ALNFILE
      cat $TMPSING >> $UMAPSINGLE
      cat $TMPPAIR >> $UMAP
    done
    pigz -f $UMAPSINGLE
    repair.sh in=$UMAP out=$UMAP.gz overwrite=true
    unlink $UMAP
  fi
  if [[ ! -f $UMAP.gz && ! -f $UMAPSINGLE.gz ]]; then
    echo "Need unmapped FASTQ file, skipping $STRAIN ($FILEBASE) ($UMAP $UMAPSINGLE)"
  else
    if [ ! -d $UNMAPPEDASM/$STRAIN ]; then
      spades.py --pe-12 1 $UMAP.gz --pe-s 1 $UMAPSINGLE.gz -o $UNMAPPEDASM/$STRAIN -t $CPU -m $MEM --careful
    else
      echo "Already ran $UNMAPPEDASM/$STRAIN skipping"
    fi
  fi
done
