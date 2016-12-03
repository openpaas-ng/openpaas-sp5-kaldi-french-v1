#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# begin configuration section
dir=data/local/lm # language model directory
text=data/local/dict/corpus # training data file
order=3 # Language model order
lexicon=lexicon/lexicon # lexicon file path, default is lexicon/lexicon. This is used with KALDI LM
lm_system=KALDI # Language model toolkit
lms_systems=
lms_lambdas=
# end configuration section
. path.sh
. utils/parse_options.sh

if [ "$#" -ne 0 ]; then
  echo "Usage: $0 [option]"
  echo "e.g.: $0 --order 3 --lm_system KALDI --lexicon lexicon/lexicon"
  echo "Options:"
  echo " --order      	# Language model order"
  echo " --lexicon    	# lexicon file path, default is lexicon/lexicon. This is used with --lm-system KALDI"
  echo " --dir          # destination language model directory, default data/local/lm"
  echo " --text         # training data file, default data/local/dict/corpus"
  echo " --lm_system  	# KALDI|SRILM|IRSTLM|MERGING"
  echo " # The following options are used when MERGING option is specified. See ngram -help for inforamtion"
  echo " --lms_systems	# KALDI;SRILM;IRSTLM ';' is used to separate between merging systemsé"
  echo " --lms_lambdas 	# 1;.2;.2 ';' is used to separate between merging systemsé, default value is .5 for all language models"
  exit 1
fi


mkdir -p $dir

if [ $lm_system == "KALDI" ]; then
    	c=`pwd`
	( # First make sure the kaldi_lm toolkit is installed.
	 cd $KALDI_ROOT/tools || exit 1;
	 if [ -d kaldi_lm ]; then
	   echo "Not installing the kaldi_lm toolkit since it is already there."
	 else
	   echo "Downloading and installing the kaldi_lm tools"
	   if [ ! -f kaldi_lm.tar.gz ]; then
	     wget http://www.danielpovey.com/files/kaldi/kaldi_lm.tar.gz || exit 1;
	   fi
	   tar -xvzf kaldi_lm.tar.gz || exit 1;
	   cd kaldi_lm
	   make || exit 1;
	   echo "Done making the kaldi_lm tools"
	 fi
	) || exit 1;

	cd $c
	[ ! -f $text ] && echo "$0: No such training file $text" && exit 1;

	cleantext=$dir/text.no_oov

	cat $text | awk -v lex=$lexicon 'BEGIN{while((getline<lex) >0){ seen[$1]=1; } } 
	{for(n=1; n<=NF;n++) {  if (seen[$n]) { printf("%s ", $n); } else {printf("<UNK> ",$n);} } printf("\n");}' \
	> $cleantext || exit 1;

	cat $cleantext | awk '{for(n=2;n<=NF;n++) print $n; }' | sort | uniq -c | \
	sort -nr > $dir/word.counts || exit 1;

	cat $cleantext | awk '{for(n=2;n<=NF;n++) print $n; }' | \
	cat - <(grep -w -v '!SIL' $lexicon | awk '{print $1}') | \
	sort | uniq -c | sort -nr > $dir/unigram.counts || exit 1;

	# note: we probably won't really make use of <UNK> as there aren't any OOVs
	cat $dir/unigram.counts  | awk '{print $2}' | get_word_map.pl "<s>" "</s>" "<UNK>" > $dir/word_map \
	|| exit 1;

	# note: ignore 1st field of train.txt, it's the utterance-id.
	cat $cleantext | awk -v wmap=$dir/word_map 'BEGIN{while((getline<wmap)>0)map[$1]=$2;}
	{ for(n=2;n<=NF;n++) { printf map[$n]; if(n<NF){ printf " "; } else { print ""; }}}' | gzip -c >$dir/train.gz \
	|| exit 1;

	train_lm.sh --arpa --lmtype ${order}gram $dir 2>/dev/null || exit 1;
	cp $dir/${order}gram/lm_unpruned.gz $dir/KALDI.$order.gz
	rm $cleantext $dir/word.counts $dir/unigram.counts $dir/word_map $dir/wordlist.mapped $dir/train.gz
	rm -rd $dir/${order}gram

elif [ $lm_system == "SRILM" ]; then
loc=`which ngram-count`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64 
  else
    sdir=$KALDI_ROOT/tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo "You appear to not have SRILM tools installed, either on your path,"
    echo "or installed in $sdir.  See tools/install_srilm.sh for installation"
    echo "instructions."
    exit 1
  fi
fi
	ngram-count -order $order -kndiscount -interpolate -text $text -lm $dir/SRILM.$order.gz

elif [ $lm_system == "IRSTLM" ]; then
if ! command -v ngt >/dev/null 2>&1 ; then
  echo "$0: Error: the IRSTLM is not available or compiled" >&2
  echo "$0: Error: We used to install it by default, but." >&2
  echo "$0: Error: this is no longer the case." >&2
  echo "$0: Error: To install it, go to $KALDI_ROOT/tools" >&2
  echo "$0: Error: and run extras/install_irstlm.sh" >&2
  exit 1
fi
	add-start-end.sh < $text > $text.s
	ngt -i=$text.s -n=$order -o=$dir/irstlm.${order}.ngt -b=yes 2>/dev/null
	tlm -tr=$dir/irstlm.${order}.ngt -n=$order -lm=wb -o=$dir/IRSTLM.${order} 2>/dev/null
	gzip $dir/IRSTLM.${order}
	rm $dir/irstlm.${order}.ngt $text.s

elif [ $lm_system == "MERGING" ]; then
	#lms_tmp=$(echo $lms_systems | awk '{print tolower($0)}' | tr ";" "\n")
	lms_tmp=$(echo $lms_systems | tr ";" "\n")
	lambda_tmp=$(echo $lms_lambdas | tr ";" "\n")
	req=
	t=0
	for i in $lms_tmp; do
	    lms[$t]=$i
	    t=$((t + 1))
	done
	t=0
	for i in $lambda_tmp; do
	    lambdas[$t]=$i
	    t=$((t + 1))
	done
	t=0
	for lm in ${lms[*]}; do
	    [ -z ${lambdas[$t]} ] && lambdas[$t]=0.5
	    [ $t -eq 0 ] && req="$req -lm $dir/$lm.${order}.gz"
	    [ $t -eq 1 ] && req="$req -mix-lm $dir/$lm.${order}.gz -lambda "${lambdas[$t]}
	    [ $t -ge 2 ] && req="$req -mix-lm$t $dir/$lm.${order}.gz -mix-lambda$t "${lambdas[$t]}
	    t=$((t + 1))
	done
	#echo $req
	#n=$(echo $lms_systems | awk '{print tolower($0)}' | sed -e 's/;/./')
	n=$(echo $lms_systems | sed -e 's/;/./g')
	ngram -order $order $req -write-lm $dir/$n.$order.gz

else
	echo "language model system is not recognized. Please verify the name of the system." && exit 1

fi




