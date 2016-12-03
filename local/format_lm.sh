#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# begin configuration section
src_dir=data/lang
lm_dir=data/local/lm
lm_order=3
liaison=false
# end configuration section

. utils/parse_options.sh || exit 1;

if [ $# -ne 0 ]; then
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "   --src_dir  <dir>           # source lang directory, default data/lang..."
  echo "   --lm_dir   <dir>           # is the directory in which the language model is stored, default data/local/lm..."
  echo "   --lm_order 		      # the language model order, default 3"
  echo "   --liaison 		      # liaison transformation, default false"
  exit 1
fi



if [ ! -d $lm_dir ]; then
  echo "$0: expected source LM directory $lm_dir to exist"
  exit 1;
fi
if [ ! -f $src_dir/words.txt ]; then
  echo "$0: expected $src_dir/words.txt to exist."
  exit 1;
fi

for file in $lm_dir/*.$lm_order.gz; do
  lm_suffix=$(echo $file | sed -e "s/\.$lm_order.gz//" -e 's/data\/local\/lm\///')
  test=${src_dir}_test_${lm_suffix}
  echo $test
  [ -d $test ] && rm -r $test
  mkdir -p $test
  cp -r ${src_dir}/* $test
  gunzip -c $lm_dir/$lm_suffix.$lm_order.gz | \
  arpa2fst --disambig-symbol=#0 \
	   --read-symbol-table=$test/words.txt - $test/G.fst
  fstisstochastic $test/G.fst 
  [ $liaison == false ] && utils/validate_lang.pl --skip-determinization-check $test;
  [ $liaison == true ] && local/language_liaison/validate_lang_liaison.pl --skip-determinization-check $test;
done

