#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# Begin configuration section.
stage_dbn=2
# End configuration section.


if [ $stage_dbn -le 0 ]; then
  # Store fMLLR features

  # train
  dir=
  steps/nnet/make_fmllr_feats.sh --nj $train_nj \
     --transform-dir $exp_dir/tri4a_ali \
     $dir data/train $exp_dir/tri4a $data_fmllr/train/{log,data} || exit 1

  for data in $data_decode; do
    steps/nnet/make_fmllr_feats.sh --nj $decode_nj \
      --transform-dir $exp_dir/tri4a/decode_dev_KALDI \
      $dir data/dev $exp_dir/tri4a $data_fmllr/$data/{log,data}
  done

  # split the data if data/dev is not specified : 90% train 10% cross-validation (held-out)
  [ "$data_dev" == "" ] && utils/subset_data_dir_tr_cv.sh $data_fmllr/train $data_fmllr/train_tr90 $data_fmllr/train_cv10
fi

if [ $stage_dbn -le 1 ]; then
  # Pre-train DBN, i.e. a stack of RBMs
  steps/nnet/pretrain_dbn.sh --rbm-iter 1 --nn-depth $depth $data_fmllr/train $exp_dir/nnet/pretrain-${depth}dbn || exit 1;
fi


if [ $stage_dbn -le 2 ]; then
# fine-tuning of DBN parameters
  ali=exp/tri4a_ali

  # Train
  if [ "$data_dev" == "" ]; then
    steps/nnet/train.sh --feature-transform $exp_dir/nnet/pretrain-${depth}dbn/final.feature_transform \
      --dbn $exp_dir/nnet/pretrain-${depth}dbn/$depth.dbn --hid-layers 0 --learn-rate $learn_rate \
      $data_fmllr/train_tr90 $data_fmllr/train_cv10 data/lang $exp_dir/tri4a_ali $exp_dir/tri4a_ali $exp_dir/nnet/${depth}dbn
  else
    steps/nnet/train.sh --feature-transform $exp_dir/nnet/pretrain-${depth}dbn/final.feature_transform \
      --dbn $exp_dir/nnet/pretrain-${depth}dbn/$depth.dbn --hid-layers 0 --learn-rate $learn_rate \
      $data_fmllr/train $data_fmllr/dev data/lang $exp_dir/tri4a_ali $exp_dir/tri4a_dev_ali $exp_dir/nnet/${depth}dbn
  fi

  #Decoder
  for lm in ${lms[*]}; do
    for d in $data_decode; do
      steps/nnet/decode.sh --config $decode_dnn_conf --nj $decode_nj \
        $exp_dir/tri4a/graph_$lm $data_fmllr/$d $exp_dir/nnet/${depth}dbn/decode_${d}_$lm
    done
  done
  for x in $exp_dir/nnet/${depth}dbn/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done

fi
