#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai


#CONFIGURATION
stage=1
perturb_value=1
align_dir=exp/tri4a_mfcc_ali
tri4a=exp/tri4a
output_dir=data_mfcc
dir=$output_dir/train
input_data="train"
njobs=12
dir_ubm=exp/ubm
dir_sgmm=exp/sgmm2
train_stage=-10
parallel_opts="--gpu 1"
num_threads=1
minibatch_size=512
l=5
dir_nnet=exp/nnet2/pnorm/nnet2_${l}layers
#END


if [ $stage -le 1 ]; then
  echo "Data preparation"
  combine=""
  for x in $input_data; do
    local/data_mfcc.sh --stage 1 --perturb-value $perturb_value $output_dir/${x}_mfcc data/$x mfcc $output_dir/${x}_mfcc/{log,data}
    combine=$combine $output_dir/${x}_mfcc data/$x
  done
  utils/combine_data.sh $dir $combine
fi

if [ $stage -le 2 ]; then
  echo "Align GMM SAT-FMLLR model for training dnn"
  njobs=12
  steps/align_fmllr.sh --nj $njobs $dir data/lang $tri4a $align_dir
fi

if [ $stage -le 3 ]; then
  echo ============================================================================
  echo " SGMM : SGMM Training & Decoding "
  echo ============================================================================
  #Train SGMM model
  steps/train_ubm.sh 400 $dir data/lang $align_dir $dir_ubm
  steps/train_sgmm2.sh 8000 9000 $dir data/lang $align_dir $dir_ubm/final.ubm $dir_sgmm

  #Decoder
  for lm in IRSTLM SRILM; do
   utils/mkgraph.sh data/lang_test_$lm $dir_sgmm $dir_sgmm/graph_$lm
   steps/decode_sgmm2.sh --config conf/decode.config --nj $njobs --transform-dir exp/tri4a/decode_test_$lm \
     $dir_sgmm/graph_$lm data/test $dir_sgmm/decode_test_$lm
  done
  for x in $dir_sgmm/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done
fi 


echo ============================================================================
echo "                    DNN Training & Decoding                               "
echo ============================================================================
#Train DNN model
if [ ! -f $dir_nnet/final.mdl ]; then
  steps/nnet2/train_pnorm_fast.sh --stage $train_stage \
   --samples-per-iter 400000 \
   --parallel-opts "$parallel_opts" \
   --num-threads "$num_threads" \
   --minibatch-size "$minibatch_size" \
   --num-jobs-nnet 12  --mix-up 8000 \
   --initial-learning-rate 0.01 --final-learning-rate 0.001 \
   --num-hidden-layers $l \
   --pnorm-input-dim 2000 --pnorm-output-dim 400 \
    $dir data/lang $align_dir $dir_nnet
fi

for lm in IRSTLM SRILM; do
 steps/nnet2/decode.sh --nj $njobs \
    --transform-dir exp/tri4a/decode_test_$lm \
    exp/tri4a/graph_$lm data/test $dir_nnet/decode_test_$lm
done

for x in $dir/decode_*; do
 [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done




: '
echo ============================================================================
echo "                    System Combination (SGMMs)                         	"
echo ============================================================================

for lm in IRSTLM SRILM; do
  local/score_combine.sh data/test data/lang_test_$lm ../s5/exp/sgmm2/decode_test_$lm exp/sgmm2/decode_test_$lm exp/combine1/decode_test_$lm
  local/score_combine.sh data/test data/lang_test_$lm ../s5/exp/sgmm2/decode_test_$lm exp/sgmm2_1/decode_test_$lm exp/combine2/decode_test_$lm  
  local/score_combine.sh data/test data/lang_test_$lm ../s5/exp/sgmm2/decode_test_$lm exp/sgmm2/decode_test_$lm exp/sgmm2_1/decode_test_$lm exp/combine3/decode_test_$lm  
done


echo ============================================================================
echo "                    System Combination (DNN+SGMM)                         "
echo ============================================================================

for lm in IRSTLM SRILM; do
#  local/score_combine.sh data/test data/lang_test_$lm ../s5/exp/nnet2_gpu/pnorm/nnet2_5layers/decode_test_$lm exp/nnet2_gpu/pnorm/nnet2_5layers/decode_test_$lm exp/combine_nnet2_1/decode_test_$lm
#  local/score_combine.sh data/test data/lang_test_$lm ../s5/exp/nnet2_gpu/pnorm/nnet2_5layers/decode_test_$lm ../s5/exp/sgmm2/decode_test_$lm exp/combine_sgmm_nnet2/decode_test_$lm
  local/score_combine.sh data/test data/lang_test_$lm \
	 ../s5/exp/nnet2_gpu/pnorm/nnet2_5layers/decode_test_$lm \
	../s5/exp/sgmm2/decode_test_$lm \
	exp/nnet2_gpu/pnorm/nnet2_5layers/decode_test_$lm \
	exp/sgmm2_1/decode_test_$lm \
	exp/combine_all/decode_test_$lm
done
'
