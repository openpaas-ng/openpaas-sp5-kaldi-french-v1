#!/bin/bash
# Copyright (C) 2016, Linagora, Ilyes Rebai
# INSTALL Sox package
# INSTALL KALDI_LM; SRILM; IRSTLM
# begin configuration section
data=speech_data # Set this to directory where you put the data
adapt=false # Set this to true if you want to make the data as the vocabulary file,
	    # example: dès que (original text) => dès_que (vocabulary word)
liaison=true # Set this to true if you want to makes lexicon while taking into account liaison for French language
njobs=12
# end configuration section
. ./path.sh

echo "Preparing data as Kaldi data directories"
for part in train test; do
 local/data_prep.sh --apply_adaptation $adapt $data/$part data/$part
done

## Optional G2P training scripts.
#local/g2p/train_g2p.sh lexicon conf

echo "Preparing dictionary"
local/dic_prep.sh lexicon conf/model-2

echo "Preparing language model"
local/lm_prep.sh --order 3 --lm_system IRSTLM
local/lm_prep.sh --order 3 --lm_system SRILM

## Optional Perplexity of the built models
local/compute_perplexity.sh --order 3 --text data/test test IRSTLM
local/compute_perplexity.sh --order 3 --text data/test test SRILM

echo "Prepare data/lang and data/local/lang directories"
[ $liaison == false ] && echo "No liaison is applied" && \
 utils/prepare_lang.sh --position-dependent-phones true data/local/dict "!SIL" data/local/lang data/lang
[ $liaison == true ] && echo "Liaison is applied in the creation of lang directories" && \
 local/language_liaison/prepare_lang_liaison.sh --sil-prob 0.3 data/local/dict "!SIL" data/local/lang data/lang
[ ! $liaison == true ] && [ ! $liaison == false ] && echo "verify the value of the variable liaison" && exit 1

echo "Prepare G.fst and data/{train,dev,test} directories"
local/format_lm.sh --liaison $liaison


mfccdir=mfcc
for x in train test; do
steps/make_mfcc.sh --nj $njobs data/$x exp/make_mfcc/$x $mfccdir || exit 1;
steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir || exit 1;
done
utils/subset_data_dir.sh data/train 4000 data/train_4k


echo ============================================================================
echo " MonoPhone Training & Decoding "
echo ============================================================================

#Train monophone model
steps/train_mono.sh --nj $njobs data/train_4k data/lang exp/mono

#Decoder
for lm in IRSTLM SRILM; do
 utils/mkgraph.sh --mono data/lang_test_$lm exp/mono exp/mono/graph_$lm
 steps/decode.sh --config conf/decode.config --nj $njobs exp/mono/graph_$lm data/test exp/mono/decode_test_$lm
done
for x in exp/mono/decode_*; do
 [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done

echo ============================================================================
echo " tri1 : TriPhone with delta delta-delta features Training & Decoding      "
echo ============================================================================
#Align the train data using mono-phone model
steps/align_si.sh --nj $njobs data/train data/lang exp/mono exp/mono_ali
#Train Deltas + Delta-Deltas model based on mono_ali
steps/train_deltas.sh 3000 40000 data/train data/lang exp/mono_ali exp/tri1

#Decoder
for lm in IRSTLM SRILM; do
 utils/mkgraph.sh data/lang_test_$lm exp/tri1 exp/tri1/graph_$lm
 steps/decode.sh --config conf/decode.config --nj $njobs exp/tri1/graph_$lm data/test exp/tri1/decode_test_$lm
done
for x in exp/tri1/decode_*; do
[ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done

echo ============================================================================
echo " tri2b : LDA + MLLT Training & Decoding "
echo ============================================================================
#Align the train data using tri1 model
steps/align_si.sh --nj $njobs data/train data/lang exp/tri1 exp/tri1_ali
#Train LDA + MLLT model based on tri1_ali
steps/train_lda_mllt.sh --splice-opts "--left-context=3 --right-context=3" 4000 60000 data/train data/lang exp/tri1_ali exp/tri2b

#Decoder
for lm in IRSTLM SRILM; do
 utils/mkgraph.sh data/lang_test_$lm exp/tri2b exp/tri2b/graph_$lm
 steps/decode.sh --config conf/decode.config --nj $njobs exp/tri2b/graph_$lm data/test exp/tri2b/decode_test_$lm
done
for x in exp/tri2b/decode_*; do
[ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done

echo ============================================================================
echo " tri4a : LDA+MLLT+SAT Training & Decoding "
echo ============================================================================
steps/align_si.sh --nj $njobs data/train data/lang exp/tri2b exp/tri2b_ali
#Train GMM SAT model based on Tri2b_ali
steps/train_sat.sh 4000 60000 data/train data/lang exp/tri2b_ali exp/tri4a

#Decoder
for lm in IRSTLM SRILM; do
# utils/mkgraph.sh data/lang_test_$lm exp/tri4a exp/tri4a/graph_$lm
 steps/decode_fmllr.sh --config conf/decode.config --nj $njobs exp/tri4a/graph_$lm data/test exp/tri4a/decode_test_$lm
done
for x in exp/tri4a/decode_*; do
[ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done

echo ============================================================================
echo " SGMM : SGMM Training & Decoding "
echo ============================================================================
#Align the train data using tri4a model
steps/align_fmllr.sh --nj $njobs data/train data/lang exp/tri4a exp/tri4a_ali

#Train SGMM model based on the GMM SAT model
steps/train_ubm.sh 400 data/train data/lang exp/tri4a_ali exp/ubm_400
steps/train_sgmm2.sh 8000 9000 data/train data/lang exp/tri4a_ali exp/ubm_400/final.ubm exp/sgmm2

#Decoder
for lm in IRSTLM SRILM; do
 utils/mkgraph.sh data/lang_test_$lm exp/sgmm2 exp/sgmm2/graph_$lm
 steps/decode_sgmm2.sh --config conf/decode.config --nj $njobs --transform-dir exp/tri4a/decode_test_$lm \
   exp/sgmm2/graph_$lm data/test exp/sgmm2/decode_test_$lm
done
for x in exp/sgmm2/decode_*; do
[ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done


echo ============================================================================
echo "                    DNN Training & Decoding                        	"
echo ============================================================================
train_stage=-10
parallel_opts="--gpu 1"
num_threads=1
minibatch_size=512
l=5
dir=exp/nnet2/pnorm/nnet2_${l}layers

if [ ! -f $dir/final.mdl ]; then
  steps/nnet2/train_pnorm_fast.sh --stage $train_stage \
   --samples-per-iter 400000 \
   --parallel-opts "$parallel_opts" \
   --num-threads "$num_threads" \
   --minibatch-size "$minibatch_size" \
   --num-jobs-nnet 12  --mix-up 8000 \
   --initial-learning-rate 0.01 --final-learning-rate 0.001 \
   --num-hidden-layers $l \
   --pnorm-input-dim 2000 --pnorm-output-dim 400 \
    data/train data/lang exp/tri4a_ali $dir
fi

for lm in IRSTLM SRILM; do
 steps/nnet2/decode.sh --nj $njobs \
    --transform-dir exp/tri4a/decode_test_$lm \
    exp/tri4a/graph_$lm data/test $dir/decode_test_$lm
done

for x in $dir/decode_*; do
 [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done

