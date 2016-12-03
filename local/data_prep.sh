#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# Begin configuration section.
apply_adaptation=false # Language model toolkit
sample_rate=16000 # Sample rate of wav file.
path=local
# End configuration section.
. utils/parse_options.sh

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [option] <src-dir> <dst-dir>"
  echo "e.g.: $0 --apply_adaptation false /french_speech/train /data/train"
  echo "Options:"
  echo " --path 		 # Path to the dataset"
  echo " --apply_adaptation      # Apply text adaptation according to the lexicon. Default=false"
  echo " --sample_rate           # output audio file sample rate"
  exit 1
fi

src=$1
dst=$2

mkdir -p $dst || exit 1;

[ ! -d $src ] && echo "$0: no such directory $src" && exit 1;

rm -f $dst/*

wav_scp=$dst/wav.scp;
trans=$dst/text;
utt2spk=$dst/utt2spk;
spk2utt=$dst/spk2utt;
segments=$dst/segments;

cat lexicon/lexicon | awk '{print $1}' | egrep "_|-|'" | egrep -v '^-|-$|\)$' > lexicon/lex

for reader_dir in $(find $src -mindepth 1 -maxdepth 1 -type d | sort); do
  reader=$(basename $reader_dir)

  for chapter_dir in $(find -L $reader_dir/ -mindepth 1 -maxdepth 1 -type d | sort); do
    chapter=$(basename $chapter_dir)

    find $chapter_dir/ -iname "*.wav" | sort | xargs -I% basename % .wav | \
      awk -v "dir=$chapter_dir" -v "sr=$sample_rate" '{printf "%s /usr/bin/sox %s/%s.wav -t wav -r %s -c 1 - |\n", $0, dir, $0, sr}' >> $wav_scp|| exit 1

    chapter_trans=$chapter_dir/${reader}-${chapter}.trans.txt
    [ ! -f  $chapter_trans ] && echo "$0: expected file $chapter_trans to exist" && exit 1
    if [ $apply_adaptation == "true" ]; then
    	$path/french_txt.pl $chapter_trans > $dst/text_tmp
    	$path/file_prepare.py $trans $dst/text_tmp lexicon/lex 
    else
	$path/french_txt.pl $chapter_trans > $dst/text_tmp
	cat $dst/text_tmp | sed -e 's/  / /g' >>$trans
    fi

    awk -v "reader=$reader" -v "chapter=$chapter" '{printf "%s %s-%s\n", $1, reader, chapter}' \
      < $chapter_trans >>$utt2spk || exit 1

  done
done

rm $dst/text_tmp

spk2utt=$dst/spk2utt
utils/utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt || exit 1

ntrans=$(wc -l <$trans)
nutt2spk=$(wc -l <$utt2spk)
! [ "$ntrans" -eq "$nutt2spk" ] && \
  echo "Inconsistent #transcripts($ntrans) and #utt2spk($nutt2spk)" && exit 1;

local/get_utt2dur.sh $dst || exit 1

cat $dst/utt2dur | awk '{print $1" "$1" 0 "$2}' > $segments

utils/validate_data_dir.sh --no-feats $dst || exit 1;

echo "Successfully prepared data in $dst"

exit 0
