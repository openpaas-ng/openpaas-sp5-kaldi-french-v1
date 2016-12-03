#!/bin/bash

. path.sh

# CONFIGURATION
data_fmllr=data_mllr
njobs=12
stage=1
dir=exp/autoencoder
dir_nnet=exp/autoencoder_nnet
output_dir=data_autoencoded
#END


if [ ! -d $data_fmllr ]; then
steps/nnet/make_fmllr_feats.sh --transform-dir exp/tri4a_ali $data_fmllr/train data/train exp/tri4a $data_fmllr/{log,data}
steps/compute_cmvn_stats.sh $data_fmllr/train $data_fmllr/{log,data}
steps/nnet/make_fmllr_feats.sh --transform-dir exp/tri4a/decode_test_IRSTLM $data_fmllr/test data/test exp/tri4a $data_fmllr/{log,data}
steps/compute_cmvn_stats.sh $data_fmllr/test $data_fmllr/{log,data}
utils/subset_data_dir_tr_cv.sh --cv-spk-percent 10 $data_fmllr/train $data_fmllr/train_tr90 $data_fmllr/train_cv10
fi

if [ $stage -le 2 ]; then
labels="ark:feat-to-post scp:$data_fmllr/train/feats.scp ark:- |"
run.pl $dir/log/train_nnet.log \
	  steps/nnet/train.sh --hid-layers 4 --hid-dim 256 --learn-rate 0.0001 \
	      --labels "$labels" --num-tgt 40 --train-tool "nnet-train-frmshuff --objective-function=mse" \
	          --proto-opts "--no-softmax --activation-type=<Tanh> --hid-bias-mean=-1.0 --hid-bias-range=1.0 --param-stddev-factor=0.01" \
		    $data_fmllr/train_tr90 $data_fmllr/train_cv10 dummy-dir dummy-dir dummy-dir $dir || exit 1;
fi

if [ $stage -le 3 ]; then
# Forward the data,
for x in train test; do
  steps/nnet/make_bn_feats.sh --nj 12 --remove-last-components 1 \
	  $output_dir/$x $data_fmllr/$x $dir $output_dir/$x/{log,data} || exit 1
done
fi

echo "$0: Training and extracting autoencoder features finished successfully"


if [ $stage  -le 4 ]; then
#steps/align_fmllr.sh --nj $njobs data/test data/lang exp/tri4a exp/tri4a_test_ali
steps/nnet/train.sh data-autoencoded/train data-autoencoded/test data/lang exp/tri4a_ali exp/tri4a_test_ali $dir_nnet
fi

if [ $stage -le 5 ]; then
for lm in SRILM; do
 steps/nnet/decode.sh --nj $njobs \
    exp/tri4a/graph_$lm $output_dir/test $dir_nnet/decode_test_$lm
done

for x in $dir/decode_*; do
 [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done
fi



