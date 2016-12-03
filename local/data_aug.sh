#!/bin/bash 

# Copyright (C) 2016, Linagora, Ilyes Rebai

# Begin configuration section.
augmentation_mode=
parameters=
extra_param=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
   echo "usage: $0 [options] <src-data-dir> <tgt-data-dir>";
   echo "options: "
   echo "  --augmentation-mode (speed|pitch|vtlp)  	# data augmentation approach to apply on the original data "
   echo "  --parameters (1.2;1.0;0.8)  			# parameters appropriate for this transformation mode "
   echo "  --extra-param (fonction)			# specify the function to apply on data " 
   exit 1;
fi

src=$1 # original data
dst=$2 # transformed data

######## CONFIGURATION


[[ -d $dst ]] && rm -r $dst
mkdir -p $dst $dst/tmp || exit 1;

[ ! -d $src ] && echo "$0: no such directory $src" && exit 1;

wav=$dst/tmp/wav.scp; # utt_id wav_src
text=$dst/tmp/text; # utt_id text
utt2spk=$dst/tmp/utt2spk; # utt_id spk_id
utt2warp=$dst/tmp/utt2warp; # utt_id spk_id
spk2utt=$dst/spk2utt; # spk_id utt_ids

if [ $augmentation_mode == "speed" ]; then
   if [ "$extra_param" == "" ]; then echo "Transformation function is not defined. So, sox tempo function is applied"; fi
   [[ "$parameters" == "" ]] && echo "you need to specify the speed values, example: --parameters '1.2;1.0;0.8'" && exit 1
   for param in $(echo $parameters | tr ";" "\n"); do
	# Prepare the transcription file
        while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_speed-$param-$(echo $utt_id | cut -d- -f3)
	   trans=$(echo $line | cut -d ' ' -f2-)
	   echo $new_utt_id $trans >> $text
	done < "$src/text"

	# Prepare the utt2spk file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_speed-$param-$(echo $utt_id | cut -d- -f3)
	   spk_id=$(echo $line | cut -d ' ' -f2-)
	   echo $new_utt_id $spk_id >> $utt2spk
	done < "$src/utt2spk"

	# Prepare the wav.scp file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_speed-$param-$(echo $utt_id | cut -d- -f3)
	   path_sox=$(echo $line | cut -d ' ' -f2)
	   path_wav=$(echo $line | cut -d ' ' -f3)
	   exist_param=$(echo $line | cut -d ' ' -f4-9)
	   if [ "$extra_param" != "" ]; then echo "$new_utt_id $path_sox $path_wav $exist_param - $extra_param $param - |" >> $wav
	   else echo "$new_utt_id $path_sox $path_wav $exist_param - tempo $param |" >> $wav
	   fi
	done < "$src/wav.scp"
   done
elif [ $augmentation_mode == "pitch" ]; then
   echo "sox pitch function is applied in order to create artificial speakers based on the existing ones"
   [[ "$parameters" == "" ]] && echo "you need to specify the pitch values, example: --parameters '-600;-300;0;300;600'" && exit 1
   for param in $(echo $parameters | tr ";" "\n"); do
	# Prepare the transcription file
        while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_pitch-$param-$(echo $utt_id | cut -d- -f3)
	   trans=$(echo $line | cut -d ' ' -f2-)
	   echo $new_utt_id $trans >> $text
	done < "$src/text"

	# Prepare the utt2spk file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_pitch-$param-$(echo $utt_id | cut -d- -f3)
	   new_spk_id=$(echo $line | cut -d ' ' -f2-)_pitch-$param
	   echo $new_utt_id $new_spk_id >> $utt2spk
	done < "$src/utt2spk"

	# Prepare the wav.scp file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_pitch-$param-$(echo $utt_id | cut -d- -f3)
	   path_sox=$(echo $line | cut -d ' ' -f2)
	   path_wav=$(echo $line | cut -d ' ' -f3)
	   exist_param=$(echo $line | cut -d ' ' -f4-9)
	   echo "$new_utt_id $path_sox $path_wav $exist_param - pitch $param |" >> $wav
	done < "$src/wav.scp"
   done
elif [ $augmentation_mode == "vtlp" ]; then
   echo "Vocal tract length perturbation"
   [[ "$parameters" == "" ]] && echo "you need to specify the warping factors, example: --parameters '0.9;1.0;1.1'" && exit 1
   for param in $(echo $parameters | tr ";" "\n"); do
	# Prepare the transcription file
        while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_vtlp-$param-$(echo $utt_id | cut -d- -f3)
	   trans=$(echo $line | cut -d ' ' -f2-)
	   echo $new_utt_id $trans >> $text
	done < "$src/text"

	# Prepare the utt2spk file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_vtlp-$param-$(echo $utt_id | cut -d- -f3)
	   spk_id=$(echo $line | cut -d ' ' -f2-)
	   echo $new_utt_id $spk_id >> $utt2spk
	done < "$src/utt2spk"

	# Prepare the wav.scp file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_vtlp-$param-$(echo $utt_id | cut -d- -f3)
	   path_sox=$(echo $line | cut -d ' ' -f2)
	   path_wav=$(echo $line | cut -d ' ' -f3)
	   exist_param=$(echo $line | cut -d ' ' -f4-9)
	   echo "$new_utt_id $path_sox $path_wav $exist_param - |" >> $wav
	done < "$src/wav.scp"

	# Prepare the utt2warp file
	while read -r line
	do
	   utt_id=$(echo $line | cut -d ' ' -f1)
	   new_utt_id=$(echo $utt_id | cut -d- -f1)-$(echo $utt_id | cut -d- -f2)_vtlp-$param-$(echo $utt_id | cut -d- -f3)
	   echo $new_utt_id $param >> $utt2warp
	done < "$src/utt2spk"
   done
   cat $utt2warp | sort > $dst/utt2warp
else echo "augmentation mode is not recognized." && rm -r $dst && exit 1
fi

# sort and copy files to the $dst directory and remove the temporary $dst/tmp folder
cat $text | sort > $dst/text
cat $utt2spk | sort > $dst/utt2spk
cat $wav | sort > $dst/wav.scp
rm -r $dst/tmp

# Prepare the  utt2dur file
#local/get_utt2dur.sh $dst 2>/dev/null || exit 1
# Prepare the  spk2utt file
utils/utt2spk_to_spk2utt.pl <$dst/utt2spk >$spk2utt || exit 1
utils/validate_data_dir.sh --no-feats $dst || exit 1;

echo "Successfully prepared modified data in $dst"

