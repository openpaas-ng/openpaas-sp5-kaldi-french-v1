#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# begin configuration section
dict_dir=data/local/dict # destination dictionary directory
lm_dir=data/local/lm # destination dictionary directory
text=data/test # training data file
order=3 # Language model order
# end configuration section

. utils/parse_options.sh


if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [option] <lm_system>"
  echo "e.g.: $0 --order 3 test KALDI"
  echo "Options:"
  echo " --order      	# Language model order"
  echo " --dict_dir     # destination dictionary directory, default data/local/dict"
  echo " --lm_dir       # destination language model directory, default data/local/lm"
  echo " --text         # training data file, default data/test"
  exit 1
fi


lm=$(echo $1 | sed "s/;/./g")

echo "$0: Computing perplexity using $lm language model"
corpusfile=$dict_dir/corpus_evaluation
cut -f2- -d' ' < $text/text | sed -e 's:[ ]\+: :g' | sort -u > $corpusfile
ngram -ppl $corpusfile -lm $lm_dir/$lm.$order.gz

