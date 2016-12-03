#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai
# INSTALL Sox package

# This script assumes that the mfcc features are already computed.


#CONFIGURATION
dst=data/train-mfcc
src=data/train
perturb_value=1
cmd=run.pl
compress=true
stage=1
#END

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "usage: $0 [options] <tgt-data-dir> <src-data-dir> <src-mfcc> <log-dir> <path-to-mfcc-dir>"
   echo "e.g.: $0 data/train-mfcc data/train exp/make_mfcc/train mfcc"
   echo "options: "
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --perturb-value 		                    # add-random-values function parameters"
   echo "N.B: <path-to-mfcc-dir> directory must be the same used to save the mfcc feature of <src-data-dir>"
   exit 1;
fi

dst=$1 # transformed data
src=$2 # original data
srcMfcc=$3
logdir=$4 # log directory
mfccdir=$5 # path to mfcc directory


[ ! -d $src ] && echo "$0: no such directory $src" && exit 1

# Check some files.
for f in $src/feats.scp; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

mkdir -p $dst || exit 1;

# use "name" as part of name of the archive.
name=`basename $src`


if [ $stage -le 1 ]; then

wav=$dst/wav.scp; [ -f $wav ] && rm $wav # utt_id wav_src
text=$dst/text; [ -f $text ] && rm $text # utt_id text
utt2spk=$dst/utt2spk; [ -f $utt2spk ] && rm $utt2spk # utt_id spk_id
utt2warp=$dst/utt2warp; [ -f $utt2warp ] && rm $utt2warp # utt_id spk_id
spk2utt=$dst/spk2utt; [ -f $spk2utt ] && rm $spk2utt #  spk_id utt_ids

while read -r line
do
   utt_id=$(echo $line | cut -d ' ' -f1)
   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)-$perturb_value-$(echo $utt_id | cut -d- -f3)
   trans=$(echo $line | cut -d ' ' -f2-)
   echo $new_utt_id $trans >> $text
done < "$src/text"

# Prepare the utt2spk file
while read -r line
do
   utt_id=$(echo $line | cut -d ' ' -f1)
   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)-$perturb_value-$(echo $utt_id | cut -d- -f3)
   spk_id=$(echo $line | cut -d ' ' -f2-)
   echo $new_utt_id $spk_id-$perturb_value >> $utt2spk
done < "$src/utt2spk"

# Prepare the wav.scp file
while read -r line
do
   utt_id=$(echo $line | cut -d ' ' -f1)
   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)-$perturb_value-$(echo $utt_id | cut -d- -f3)
   param=$(echo $line | cut -d ' ' -f2-)
   echo $new_utt_id $param >> $wav
done < "$src/wav.scp"

# Prepare the utt2warp file
if [ -f $src/utt2warp ]; then
   while read -r line
   do
      utt_id=$(echo $line | cut -d ' ' -f1)
      new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)-$perturb_value-$(echo $utt_id | cut -d- -f3)
      warp=$(echo $line | cut -d ' ' -f2-)
      echo $new_utt_id $warp >> $utt2warp
   done < "$src/utt2warp"
fi

# Prepare the  utt2dur file
#local/get_utt2dur.sh $dst 2>/dev/null || exit 1
# Prepare the  spk2utt file
utils/utt2spk_to_spk2utt.pl <$dst/utt2spk >$spk2utt || exit 1
# Validate directory 
utils/validate_data_dir.sh --no-feats $dst || exit 1;

echo "Successfully prepared data in $dst"

fi

if [ $stage -le 2 ]; then
  mkdir -p $mfccdir $logdir
  echo "Compute modified MFCC feature based on the precomputed MFCC in $src"
  [ ! -f $srcMfcc/raw_mfcc_${name}.1.ark ] && echo "$0: no raw mfcc matrices for $name data are in $srcMfcc folder" && exit 1
  rm $mfccdir/raw_pert*_${name}.*

  nj=$(echo $srcMfcc/raw_mfcc_${name}.*.ark | tr " " "\n" | wc -l)

  for ((i=1;i<=nj;i++)); do
    while read -r line
    do
      utt_id=$(echo $line | cut -d ' ' -f1)
      new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)-$perturb_value-$(echo $utt_id | cut -d- -f3)
      echo $new_utt_id >> $mfccdir/raw_pert_mfcc_${name}.$i.scp
    done < "$srcMfcc/raw_mfcc_${name}.$i.scp"
  done


  $cmd JOB=1:$nj $logdir/make_mfcc_${name}.JOB.log \
    local/features/add-random-values --wav-scp=$mfccdir/raw_pert_mfcc_${name}.JOB.scp --perturbation-value=$perturb_value --compress=$compress ark:$srcMfcc/raw_mfcc_${name}.JOB.ark \
      ark,scp:$mfccdir/raw_perturbed_mfcc_$name.JOB.ark,$mfccdir/raw_perturbed_mfcc_$name.JOB.scp || exit 1;

  for ((n=1; n<=nj; n++)); do
    cat $mfccdir/raw_perturbed_mfcc_$name.$n.scp >> $dst/feats.scp
    rm  $mfccdir/raw_pert_mfcc_${name}.$n.scp
  done
  steps/compute_cmvn_stats.sh $dst $logdir $mfccdir || exit 1
  cp $mfccdir/cmvn_train_mfcc.scp $dst/cmvn.scp || exit 1
fi

