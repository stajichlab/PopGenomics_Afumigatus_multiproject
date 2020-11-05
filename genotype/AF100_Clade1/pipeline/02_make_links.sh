#!/usr/bin/bash

pushd gvcf
python ../scripts/select_strains.py ../strains.txt | bash

