#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
#           2014  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# begin configuration section.
cmd=run.pl
#end configuration section.

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <target-dir> <predict-dir>"
  echo "e.g.: $0  exp/tri4a_dev_ali exp/sgmm/decode_dev"
  exit 1
fi

utt_phone () {
    echo "$0: Transform the ctm file into utterance phones file"
    fphone=$1 #src ctm file
    fuphone=$2 #dst utt_phone file
    nbr=$(wc -l < $fphone)
    ligne=$(sed -n "1 p" $fphone)
    utt_old=$(echo $ligne | cut -d ' ' -f1)
    ph=$(echo $ligne | cut -d ' ' -f5)
    tran="$utt_old $ph"
    i=1
    while read line
    do
    if [ $i -ne 1 ]; then
      utt=$(echo $line | cut -d ' ' -f1)
      ph=$(echo $line | cut -d ' ' -f5)
      if [ "$utt_old" == "$utt" ]; then
         tran="$tran $ph"
      else
         echo $tran >> $fuphone
        utt_old=$utt
         tran="$utt_old $ph"
      fi
      [ $i -eq $nbr ] && echo $tran >> $fuphone
    fi
    i=$((i+1))
    done < $fphone
}



target_dir=$1
predict_dir=$2
target_file=$target_dir/tr_phone.txt
predict_file=$predict_dir/pr_phone.txt


if [ ! -f $target_file ]; then
  echo "$0: Target phones extraction"
  ctm_file=$target_dir/ctm_phone.txt
  for i in $target_dir/ali.*.gz; do 
    ali-to-phones --ctm-output $target_dir/final.mdl ark:"gunzip -c $i|" ${i%.gz}.ctm
  done
  cat $target_dir/*.ctm > $ctm_file
  rm $target_dir/*.ctm
  utt_phone $ctm_file $target_file
  rm $ctm_file
fi

if [ ! -f $predict_file ]; then
  echo "$0: Predicted phones extraction"
  ctm_file=$predict_dir/ctm_phone.txt
  for i in $predict_dir/lat.*.gz; do 
    $cmd $predict_dir/log/make_phone.log \
    lattice-align-phones --replace-output-symbols=true $predict_dir/../final.mdl "ark:gunzip -c $i|" ark:- \| \
     lattice-to-ctm-conf ark:- ${i%.gz}.ctm || exit 1;
  done
  cat $predict_dir/*.ctm > $ctm_file || exit 1;
  rm $predict_dir/*.ctm
  utt_phone $ctm_file $predict_file
  rm $ctm_file
fi

compute-wer --text --mode=present ark:$target_file ark:$predict_file
