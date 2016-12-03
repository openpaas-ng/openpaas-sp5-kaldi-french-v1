#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai



# CONFIGURATION
njobs=2
dir="exp/nnet2_gpu/pnorm/nnet2_4layers \
     exp/nnet2_gpu/pnorm/nnet2_5layers" #nnet2 directories
dst=data-nnet-combine
src=data


for x in train dev test; do
  output_dir=$dst/$x
  srcdata=$src/$x
# Apply align to have the trans.* files:
# Get fmllr transform for training data from align dir (based on the tri4a model)
  transform_dir=exp/tri4a/decode_${x}_KALDI
  [ "$x"=="train" ] && transform_dir=exp/tri4a_ali
  [ ! -f $transform_dir/trans.1 ] && echo "Apply align or decode of the SAT+fmllr model to have the FMLLR trans files" && exit 1 

# Extract the predicted target values from the set of neural network models
  cmd=run.pl
  for nnet in $(echo $dir | tr " " "\n"); do
    name=`basename $nnet`
    output_dir=$output_dir/$name
    local/combine/nnet/extract_nnet2_outputs.sh --nj $njobs --use-gpu yes --transform-dir $transform_dir $output_dir $srcdata $nnet $output_dir/{log,data}
  done
done

[ ! -d exp/nnet2_gpu/pnorm/4layers_ali ] && echo "align directory for train data is not present" && exit 1
[ ! -d exp/nnet2_gpu/pnorm/4layers_dev_ali ] && echo "align directory for dev data is not present" && exit 1

nnet=nnet2_4layers
dnn_dir=exp/nnet/2_4layers # 2 nnet inputs trained on 4 layers architecture
local/combine/nnet/train_nnet.sh $dst/train/$nnet $dst/dev/$nnet data/lang exp/nnet2_gpu/pnorm/4layers_ali exp/nnet2_gpu/pnorm/4layers_dev_ali $dnn_dir

njobs=2
for lm in IRSTLM KALDI; do
  local/combine/nnet/decode_nnet.sh --nj 2 exp/tri4a/graph_$lm $dst/dev/$nnet $dnn_dir/decode_dev_$lm
done

for x in $dnn_dir/decode_*; do
  [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done
