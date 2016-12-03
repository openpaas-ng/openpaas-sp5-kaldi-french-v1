#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# begin configuration section
dir=data/local/dict # destination dictionary directory
text=data/train # training data file
# end configuration section

. utils/parse_options.sh || exit 1;

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [option] <lexicon-src-dir> <g2p-model-file>"
  echo "e.g.: $0 lexicon/ model-1"
  echo "Options"
  echo "   --dir  <dir>           # destination dictionary directory, default data/local/dict"
  echo "   --text         	  # training data file, default data/train"
  exit 1
fi


lexdir=$1 #lexicon directory
g2p_model=$2 #graphem to phoneme model


mkdir -p $dir


lexicon=$lexdir/lexicon
if [ ! -f $lexicon ]; then
  echo "$0: no such file $lexicon"
  exit 1;
fi

echo "*************Dictionary preparation started*************"

echo "--- Preparing the corpus from data/train/text transcripts ---"
corpusfile=$dir/corpus
cut -f2- -d' ' < $text/text | sed -e 's:[ ]\+: :g' > $corpusfile

echo "--- preparing full vocabulary file ---"
sed 's/ /\n/g' $corpusfile | sort -u -f | grep '[^[:blank:]]' > $dir/vocab-full.txt
sed -i '1i-pau-\n</s>\n<s>\n<unk>' $dir/vocab-full.txt

echo "--- Searching for OOV words ---"
awk 'NR==FNR{words[$1]; next;} !($1 in words)' $lexicon $dir/vocab-full.txt | egrep -v '<.?s>' > $dir/vocab-oov.txt

echo "--- Preparing pronunciations for OOV words ---"
g2p.py --model=$g2p_model --apply $dir/vocab-oov.txt > $dir/lexicon-oov.txt 2>/dev/null

echo "--- Combining pronunciations of OOV words with the existing lexicon ---"
cat $dir/lexicon-oov.txt $lexicon | sed -e 's/  /\t/g' | sort > $dir/lexicon.txt

echo "--- Preparing phone files ---"
echo SIL > $dir/silence_phones.txt
echo SIL > $dir/optional_silence.txt
grep -v -w sil $dir/lexicon.txt | awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' | sort > $dir/nonsilence_phones.txt

echo "--- Adding SIL to the lexicon ..."
sed -i '1i<UNK> SIL' $dir/lexicon.txt
echo -e "!SIL\tSIL" >> $dir/lexicon.txt

touch $dir/extra_questions.txt # Some downstream scripts expect this file exists, even if empty

echo "*************Dictionary preparation succeeded*************"
