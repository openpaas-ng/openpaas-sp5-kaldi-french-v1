echo ============================================================================
echo "                    System Combination		                        "
echo ============================================================================

path="exp/nnet2_gpu/pnorm"
lm=KALDI
m=" $path/nnet2_4layers/decode_dev_$lm"
for i in 5 6 7; do
  m+=" $path/nnet2_${i}layers/decode_dev_$lm"
  local/score_combine.sh data/dev data/lang_test_$lm $m $path/combine_$i/decode_dev_$lm
done
for x in exp/nnet2_gpu_fr/pnorm/combine_*/decode_dev_*; do [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh; done
