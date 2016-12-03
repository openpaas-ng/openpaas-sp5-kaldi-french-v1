




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
