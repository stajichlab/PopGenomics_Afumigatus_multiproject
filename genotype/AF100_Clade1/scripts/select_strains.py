#!/usr/bin/env python3
import os, sys, re
top="/bigdata/stajichlab/shared/projects/Population_Genomics/A_fumigatus/align"
tokeep="strains.txt"
if len(sys.argv) > 1:
    tokeep = sys.argv[1]

keep = {}
with open(tokeep,"r") as fh:
    for strain in fh:
        keep[strain.strip()] = 1

dropext = re.compile(r'(\S+)\.g\.vcf\.gz')

for align in os.listdir(top):
    for fname in os.listdir(os.path.join(top,align,"Variants")):
            if fname.endswith(".g.vcf.gz") or fname.endswith(".g.vcf.gz.tbi"):
                base=os.path.basename(fname)
                m = dropext.search(base)
                if m:
                    name=m.group(1)
                    #print(name)
                    if name in keep:
                        print("ln -s {} .".format(os.path.join(top,align,"Variants",fname)))
