#!/bin/bash
#SBATCH -N 1 -n 16 --mem 32gb --out logs/bwa.%a.log --time 8:00:00
module load bwa
module load samtools/1.11
module load picard
module load gatk/4
module load java/13

hostname

MEM=32g
FASTQEXT=fq
INDIR=input
TOPOUTDIR=tmp
ALNFOLDER=aln
HTCEXT=cram
HTCFORMAT=cram
GENOMESTRAIN=Af293
CENTER=UCR
SAMPINFO=samples.csv

mkdir -p $ALNFOLDER
mkdir -p $TOPOUTDIR

if [ -f config.txt ]; then
  source config.txt
fi
if [ -z $REFGENOME ]; then
  echo "NEED A REFGENOME - set in config.txt and make sure 00_index.sh is run"
  exit
fi

if [ ! -f $REFGENOME.dict ]; then
  echo "NEED a $REFGENOME.dict - make sure 00_index.sh is run"
fi
mkdir -p $TOPOUTDIR

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
TEMP=/scratch

MAX=$(wc -l $SAMPINFO | awk '{print $1}')
if [ $N -gt $MAX ]; then
  echo "$N is too big, only $MAX lines in $SAMPINFO"
  exit
fi

IFS=,
tail -n +2 $SAMPINFO | sed -n ${N}p | while read SRA STRAIN SAMPLE CTR EXPR PROJ
do

  # BEGIN THIS PART IS PROBABLY PROJECT SPECIFIC
  STRAIN=$(echo "$STRAIN" | perl -p -e 's/ /_/')
  PAIR1=$INDIR/${SRA}_1.$FASTQEXT.gz
  PAIR2=$INDIR/${SRA}_2.$FASTQEXT.gz
  PREFIX=$SRA
  # END THIS PART IS PROBABLY PROJECT SPECIFIC
  echo "STRAIN is $STRAIN $PAIR1 $PAIR2"
  TMPBAMFILE=$TEMP/$SRA.unsrt.bam
  SRTED=$TOPOUTDIR/$SRA.srt.bam
  DDFILE=$TOPOUTDIR/$SRA.DD.bam
  FINALFILE=$ALNFOLDER/$STRAIN.$SRA.$HTCEXT

  READGROUP="@RG\tID:$SRA\tSM:$STRAIN\tLB:$SRA\tPL:illumina\tCN:$CENTER"

  if [ ! -s $FINALFILE ]; then
    if [ ! -s $DDFILE ]; then
      if [ ! -s $SRTED ]; then
        if [ -e $PAIR1 ]; then
          if [ ! -f $TMPBAMFILE ]; then
		  if [ ! -f $PAIR2 ]; then
			bwa mem -t $CPU -R $READGROUP $REFGENOME $PAIR1 | samtools view -1 -o $TMPBAMFILE
		  else
            		bwa mem -t $CPU -R $READGROUP $REFGENOME $PAIR1 $PAIR2 | samtools view -1 -o $TMPBAMFILE
		fi
          fi
        else
          echo "Cannot find $PAIR1, skipping $STRAIN"
          exit
        fi
        samtools fixmate --threads $CPU -O bam $TMPBAMFILE $TEMP/$SRA.fixmate.bam
        samtools sort --threads $CPU -O bam -o $SRTED -T $TEMP $TEMP/$SRA.fixmate.bam
        if [ -f $SRTED ]; then
          rm -f $TEMP/${SRA}.fixmate.bam $TMPBAMFILE
        fi
      fi # SRTED file exists or was created by this block

      time java -jar $PICARD MarkDuplicates I=$SRTED O=$DDFILE \
      METRICS_FILE=logs/$SRA.$STRAIN.dedup.metrics CREATE_INDEX=true VALIDATION_STRINGENCY=SILENT
      if [ -s $DDFILE ]; then
        rm -f $SRTED
      fi
    fi # DDFILE is created after this or already exists

    echo "running samtools view -O $HTCFORMAT --threads $CPU --reference $REFGENOME -o $FINALFILE $DDFILE"
    samtools view -O $HTCFORMAT --threads $CPU --reference $REFGENOME -o $FINALFILE $DDFILE
    samtools index $FINALFILE

    if [ -f $FINALFILE ]; then
      rm -f $DDFILE
      rm -f $(echo $DDFILE | sed 's/bam$/bai/')
    fi
  fi #FINALFILE created or already exists
done
