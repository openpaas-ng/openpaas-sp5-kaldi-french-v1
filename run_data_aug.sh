#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai
# INSTALL Sox package

# GLOBAL CONFIGURATION

aug_mode=vtlp
dir=data_$aug_mode
data_train=train
tri4a=exp/tri4a
align_dir=exp/tri4a_${aug_mode}_ali
param="0.9;1.0;1.1"
stage=1
tri2b=0 #aplly tri2b mode for align and train tri4a
feat_nj=30
train_nj=30
decode_nj=5
dir_ubm=exp/ubm
dir_sgmm=exp/sgmm2

### NNET CONFIG BEGIN
train_stage=-10
parallel_opts="--gpu 1"
num_threads=1
minibatch_size=512
hlayer=5
pnorm_input_dim=2000
pnorm_output_dim=400
initial_lr=0.01
final_lr=0.001
dir_nnet=exp/nnet2/pnorm/nnet2_${hlayer}layers
### NNET CONFIG END

#END



if [ $stage -le 1 ]; then
  echo "$0: Preparing transformed data as Kaldi data directories"
  echo "$0: This script requires that the original data are already prepared"
  local/data_aug.sh --augmentation-mode $aug_mode --parameters "$param" data/train $dir/$data_train

  echo "$0: Extract features for the transformed data"
  steps/make_mfcc.sh --nj $feat_nj $dir/$data_train $dir/$data_train/{log,data} || exit 1;
  steps/compute_cmvn_stats.sh $dir/$data_train $dir/$data_train/{log,data} || exit 1;
fi

if [ $stage -le 2 ]; then
  echo "$0: Align Training data using GMM SAT-FMLLR model"
  steps/align_fmllr.sh --nj $train_nj $dir/$data_train data/lang $tri4a $align_dir
fi

if [ $stage -le 3 ]; then
  echo ============================================================================
  echo " SGMM : SGMM Training & Decoding "
  echo ============================================================================
  #Train SGMM model based on the GMM SAT model
  if [ ! -f $dir_ubm/final.mdl ]; then
    steps/train_ubm.sh 400 $dir/$data_train data/lang $align_dir $dir_ubm
  fi
  if [ ! -f $dir_sgmm/final.mdl ]; then
    steps/train_sgmm2.sh 8000 9000 $dir/$data_train data/lang $align_dir $dir_ubm/final.ubm $dir_sgmm
  fi

  #Decoder
  for lm in IRSTLM SRILM; do
    utils/mkgraph.sh data/lang_test_$lm $dir_sgmm $dir_sgmm/graph_$lm
    steps/decode_sgmm2.sh --config conf/decode.config --nj $decode_nj --transform-dir exp/tri4a/decode_test_$lm \
    $dir_sgmm/graph_$lm data/test $dir_sgmm/decode_test_$lm
  done
  for x in $dir_sgmm/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done

fi

if [ $stage -le 4 ]; then

  echo ============================================================================
  echo "                    DNN Training & Decoding                               "
  echo ============================================================================
  if [ ! -f $dir/final.mdl ]; then
	  steps/nnet2/train_pnorm_fast.sh --stage $train_stage \
		--samples-per-iter 400000 \
		--parallel-opts "$parallel_opts" \
		--num-threads "$num_threads" \
		--minibatch-size "$minibatch_size" \
		--num-jobs-nnet $train_nj  --mix-up 8000 \
		--initial-learning-rate $initial_lr --final-learning-rate $final_lr \
		--num-hidden-layers $hlayer \
		--pnorm-input-dim $pnorm_input_dim --pnorm-output-dim $pnorm_output_dim \
		$dir/$data_train data/lang $align_dir $dir_nnet
  fi
  for lm in IRSTLM SRILM; do
    steps/nnet2/decode.sh --nj $decode_nj \
	--transform-dir exp/tri4a/decode_test_$lm \
	exp/tri4a/graph_$lm data/test $dir_nnet/decode_test_$lm
  done
  for x in $dir_nnet/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done
fi
