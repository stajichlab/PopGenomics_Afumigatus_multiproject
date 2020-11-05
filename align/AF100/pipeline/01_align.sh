#!/bin/bash
#SBATCH -N 1 -n 16 --mem 32gb --out logs/bwa.%a.log --time 8:00:00
module load bwa
module load samtools/1.11
module load picard
module load gatk/4
module load java/13

hostname

MEM=32g
FASTQEXT=fastq
INDIR=input/DA002
TOPOUTDIR=tmp
ALNFOLDER=aln
HTCEXT=cram
HTCFORMAT=cram
GENOMESTRAIN=Af293
CENTER=UCR
SAMPFILE=samples.csv

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

MAX=$(wc -l $SAMPFILE | awk '{print $1}')
if [ $N -gt $MAX ]; then
  echo "$N is too big, only $MAX lines in $SAMPFILE"
  exit
fi

IFS=,
tail -n +2 $SAMPFILE | sed -n ${N}p | while read STRAIN FILEBASE
do
  # BEGIN THIS PART IS PROBABLY PROJECT SPECIFIC

  PREFIX=$STRAIN
  # END THIS PART IS PROBABLY PROJECT SPECIFIC
  echo "STRAIN is $STRAIN"

  SRTEDALL=$TOPOUTDIR/$STRAIN.srt.bam
  DDFILE=$TOPOUTDIR/$STRAIN.DD.bam
  FINALFILE=$ALNFOLDER/$STRAIN.$HTCEXT
  SRTEDFILES=()
  if [ ! -s $FINALFILE ]; then
    if [ ! -s $DDFILE ]; then
      if [ ! -s $SRTEDALL ]; then
        for LANE in lane1 lane2
        do
          # BEGIN THIS PART IS PROBABLY PROJECT SPECIFIC
          PAIR1=$INDIR/$LANE/${FILEBASE}_L001_R1_001.$FASTQEXT.gz
          PAIR2=$INDIR/$LANE/${FILEBASE}_L001_R2_001.$FASTQEXT.gz
          # END

          SRTED=$TOPOUTDIR/$STRAIN.$LANE.srt.bam
          TMPBAMFILE=$TEMP/$STRAIN.$LANE.unsrt.bam
          READGROUP="@RG\tID:$STRAIN.$LANE\tSM:$STRAIN\tLB:$PREFIX.$LANE\tPL:illumina\tCN:$CENTER"
          if [ ! -s $SRTED ]; then
            if [ -e $PAIR1 ]; then
              if [ ! -f $TMPBAMFILE ]; then
                bwa mem -t $CPU -R $READGROUP $REFGENOME $PAIR1 $PAIR2 | samtools view -1 -o $TMPBAMFILE
              fi
            else
              echo "Cannot find $PAIR1, skipping $STRAIN"
              exit
            fi
            samtools fixmate --threads $CPU -O bam $TMPBAMFILE $TEMP/${STRAIN}.fixmate.bam
            samtools sort --threads $CPU -n -O bam -o $SRTED -T $TEMP $TEMP/${STRAIN}.fixmate.bam

            if [ -f $SRTED ]; then
              rm -f $TEMP/${STRAIN}.fixmate.bam $TMPBAMFILE
            fi
          fi
          # SRTED file exists or was created by this block
          SRTEDFILES+=( $SRTED )
        done
        samtools merge $SRTEDALL ${SRTEDFILES[@]}
        time java -jar $PICARD MarkDuplicates I=$SRTEDALL O=$DDFILE \
          METRICS_FILE=logs/$STRAIN.dedup.metrics CREATE_INDEX=true VALIDATION_STRINGENCY=SILENT
        if [ -f $DDFILE ]; then
          rm -f $SRTEDALL ${SRTEDFILES[@]}
        fi
      fi # DDFILE is created after this or already exists

      samtools sort -O $HTCFORMAT --threads $CPU --reference $REFGENOME -o $FINALFILE $DDFILE
      samtools index $FINALFILE

      if [ -f $FINALFILE ]; then
        rm -f $DDFILE
        rm -f $(echo $DDFILE | sed 's/bam$/bai/')
      fi
    fi
  fi #FINALFILE created or already exists
done
