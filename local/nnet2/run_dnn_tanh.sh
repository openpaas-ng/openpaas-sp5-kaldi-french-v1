#!/bin/bash

# This is p-norm neural net training, with the "fast" script, on top of adapted
# 40-dimensional features.


train_stage=-100
use_gpu=true

. ./path.sh
. utils/parse_options.sh

for l in 3 4; do

if $use_gpu; then
  parallel_opts="--gpu 1"
  num_threads=1
  minibatch_size=512
  dir=exp/nnet2_gpu_fr/tanh/nnet2_${l}layers
else
  # with just 4 jobs this might be a little slow.
  num_threads=12
  parallel_opts="--num-threads $num_threads" 
  minibatch_size=128
  dir=exp/nnet2_fr/tanh/nnet2_${l}layers
fi
: '
if [ ! -f $dir/final.mdl ]; then
  steps/nnet2/train_tanh_fast.sh --stage $train_stage \
   --samples-per-iter 400000 \
   --parallel-opts "$parallel_opts" \
   --num-threads "$num_threads" \
   --minibatch-size "$minibatch_size" \
   --num-jobs-nnet 12  --mix-up 8000 \
   --initial-learning-rate 0.01 --final-learning-rate 0.001 \
   --num-hidden-layers $l --hidden-layer-dim 512 \
    data/train data/lang exp/tri4a_ali $dir
fi
'
njobs=9
for lm in IRSTLM SRILM IRSTLM.SRILM SRILM.IRSTLM; do
 steps/nnet2/decode.sh --nj $njobs \
    --transform-dir exp/tri4a/decode_test_$lm \
    exp/tri4a/graph_$lm data/test $dir/decode_test_$lm
done

for x in $dir/decode_*; do
 [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done


done
