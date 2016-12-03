#!/bin/bash

# Copyright 2012-2015  Brno University of Technology (author: Karel Vesely)
# Apache 2.0

# Begin configuration.

config=             # config, also forwarded to 'train_scheduler.sh',

# topology, initialization,
network_type=dnn    # select type of neural network (dnn,cnn1d,cnn2d,lstm),
hid_layers=4        # nr. of hidden layers (before sotfmax or bottleneck),
hid_dim=1024        # number of neurons per layer,
bn_dim=             # (optional) adds bottleneck and one more hidden layer to the NN,
dbn=                # (optional) prepend layers to the initialized NN,

proto_opts=         # adds options to 'make_nnet_proto.py',
cnn_proto_opts=     # adds options to 'make_cnn_proto.py',

nnet_init=          # (optional) use this pre-initialized NN,
nnet_proto=         # (optional) use this NN prototype for initialization,

# feature processing,
splice=5            # (default) splice features both-ways along time axis,
cmvn_opts=          # (optional) adds 'apply-cmvn' to input feature pipeline, see opts,
delta_opts=         # (optional) adds 'add-deltas' to input feature pipeline, see opts,
ivector=            # (optional) adds 'append-vector-to-feats', the option is rx-filename for the 2nd stream,
ivector_append_tool=append-vector-to-feats # (optional) the tool for appending ivectors,

feat_type=plain  
traps_dct_basis=11    # (feat_type=traps) nr. of DCT basis, 11 is good with splice=10,
transf=               # (feat_type=transf) import this linear tranform,
splice_after_transf=5 # (feat_type=transf) splice after the linear transform,

feature_transform_proto= # (optional) use this prototype for 'feature_transform',
feature_transform=  # (optional) directly use this 'feature_transform',
pytel_transform=    # (BUT) use external python transform,

# labels,
labels=            # (optional) specify non-default training targets,
                   # (targets need to be in posterior format, see 'ali-to-post', 'feat-to-post'),
num_tgt=           # (optional) specifiy number of NN outputs, to be used with 'labels=',

# training scheduler,
learn_rate=0.008   # initial learning rate,
scheduler_opts=    # options, passed to the training scheduler,
train_tool=        # optionally change the training tool,
train_tool_opts=   # options for the training tool,
frame_weights=     # per-frame weights for gradient weighting,
utt_weights=       # per-utterance weights (scalar for --frame-weights),

# data processing, misc.
copy_feats=true     # resave the train/cv features into /tmp (disabled by default),
copy_feats_tmproot=/media/storage0/kaldi.XXXX # sets tmproot for 'copy-feats',
copy_feats_compress=true # compress feats while resaving
seed=777            # seed value used for data-shuffling, nn-initialization, and training,
skip_cuda_check=false

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh; 
. parse_options.sh || exit 1;

set -euo pipefail

if [ $# != 6 ]; then
   echo "Usage: $0 <data-train> <data-dev> <lang-dir> <ali-train> <ali-dev> <exp-dir>"
   echo " e.g.: $0 data/train data/cv data/lang exp/mono_ali_train exp/mono_ali_cv exp/mono_nnet"
   echo ""
   echo " Training data : <data-train>,<ali-train> (for optimizing cross-entropy)"
   echo " Held-out data : <data-dev>,<ali-dev> (for learn-rate scheduling, model selection)"
   echo " note.: <ali-train>,<ali-dev> can point to same directory, or 2 separate directories."
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>   # config containing options"
   echo ""
   echo "  --network-type (dnn,cnn1d,cnn2d,lstm)  # type of neural network"
   echo "  --nnet-proto <file>      # use this NN prototype"
   echo "  --feature-transform <file> # re-use this input feature transform"
   echo ""
   echo "  --feat-type (plain|traps|transf) # type of input features"
   echo "  --cmvn-opts  <string>            # add 'apply-cmvn' to input feature pipeline"
   echo "  --delta-opts <string>            # add 'add-deltas' to input feature pipeline"
   echo "  --splice <N>                     # splice +/-N frames of input features"
   echo 
   echo "  --learn-rate <float>     # initial leaning-rate"
   echo "  --copy-feats <bool>      # copy features to /tmp, lowers storage stress"
   echo ""
   exit 1;
fi

data=$1
data_cv=$2
lang=$3
alidir=$4
alidir_cv=$5
dir=$6

# Using alidir for supervision (default)
if [ -z "$labels" ]; then 
  silphonelist=`cat $lang/phones/silence.csl`
  for f in $alidir/final.mdl $alidir/ali.1.gz $alidir_cv/ali.1.gz; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
  done
fi

for f in $data/feats.scp $data_cv/feats.scp; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

echo
echo "# INFO"
echo "$0 : Training Neural Network"
printf "\t dir       : $dir \n"
printf "\t Train-set : $data $(cat $data/feats.scp | wc -l), $alidir \n"
printf "\t CV-set    : $data_cv $(cat $data_cv/feats.scp | wc -l) $alidir_cv \n"
echo

mkdir -p $dir/{log,nnet}

# skip when already trained,
if [ -e $dir/final.nnet ]; then
  echo "SKIPPING TRAINING... ($0)"
  echo "nnet already trained : $dir/final.nnet ($(readlink $dir/final.nnet))"
  exit 0
fi

# check if CUDA compiled in and GPU is available,
if ! $skip_cuda_check; then cuda-gpu-available || exit 1; fi

###### PREPARE ALIGNMENTS ######
echo
echo "# PREPARING ALIGNMENTS"
if [ ! -z "$labels" ]; then
  echo "Using targets '$labels' (by force)"
  labels_tr="$labels"
  labels_cv="$labels"
else
  echo "Using PDF targets from dirs '$alidir' '$alidir_cv'"
  # training targets in posterior format,
  labels_tr="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- | ali-to-post ark:- ark:- |"
  labels_cv="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir_cv/ali.*.gz |\" ark:- | ali-to-post ark:- ark:- |"
  # training targets for analyze-counts,
  labels_tr_pdf="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |"
  labels_tr_phn="ark:ali-to-phones --per-frame=true $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |"

  # get pdf-counts, used later for decoding/aligning,
  num_pdf=$(hmm-info $alidir/final.mdl | awk '/pdfs/{print $4}')
  analyze-counts --verbose=1 --binary=false --counts-dim=$num_pdf \
    ${frame_weights:+ "--frame-weights=$frame_weights"} \
    ${utt_weights:+ "--utt-weights=$utt_weights"} \
    "$labels_tr_pdf" $dir/ali_train_pdf.counts 2>$dir/log/analyze_counts_pdf.log
  # copy the old transition model, will be needed by decoder,
  copy-transition-model --binary=false $alidir/final.mdl $dir/final.mdl
  # copy the tree
  cp $alidir/tree $dir/tree

  # make phone counts for analysis,
  [ -e $lang/phones.txt ] && analyze-counts --verbose=1 --symbol-table=$lang/phones.txt --counts-dim=$num_pdf \
    ${frame_weights:+ "--frame-weights=$frame_weights"} \
    ${utt_weights:+ "--utt-weights=$utt_weights"} \
    "$labels_tr_phn" /dev/null 2>$dir/log/analyze_counts_phones.log
fi

###### PREPARE FEATURES ######
echo
echo "# PREPARING FEATURES"
if [ "$copy_feats" == "true" ]; then
  echo "# re-saving features to local disk,"
  tmpdir=$(mktemp -d $copy_feats_tmproot)
  copy-feats --compress=$copy_feats_compress scp:$data/feats.scp ark,scp:$tmpdir/train.ark,$dir/train_sorted.scp
  copy-feats --compress=$copy_feats_compress scp:$data_cv/feats.scp ark,scp:$tmpdir/cv.ark,$dir/cv.scp
else
  # or copy the list,
  cp $data/feats.scp $dir/train_sorted.scp
  cp $data_cv/feats.scp $dir/cv.scp
fi
# shuffle the list,
utils/shuffle_list.pl --srand ${seed:-777} <$dir/train_sorted.scp >$dir/train.scp

# create a 10k utt subset for global cmvn estimates,
head -n 10000 $dir/train.scp > $dir/train.scp.10k

# for debugging, add lists with non-local features,
utils/shuffle_list.pl --srand ${seed:-777} <$data/feats.scp >$dir/train.scp_non_local
cp $data_cv/feats.scp $dir/cv.scp_non_local

###### OPTIONALLY IMPORT FEATURE SETTINGS (from pre-training) ######
ivector_dim= # no ivectors,
if [ ! -z $feature_transform ]; then
  D=$(dirname $feature_transform)
  echo "# importing feature settings from dir '$D'"
  [ -e $D/norm_vars ] && cmvn_opts="--norm-means=true --norm-vars=$(cat $D/norm_vars)" # Bwd-compatibility,
  [ -e $D/cmvn_opts ] && cmvn_opts=$(cat $D/cmvn_opts)
  [ -e $D/delta_order ] && delta_opts="--delta-order=$(cat $D/delta_order)" # Bwd-compatibility,
  [ -e $D/delta_opts ] && delta_opts=$(cat $D/delta_opts)
  [ -e $D/ivector_dim ] && ivector_dim=$(cat $D/ivector_dim)
  [ -e $D/ivector_append_tool ] && ivector_append_tool=$(cat $D/ivector_append_tool)
  echo "# cmvn_opts='$cmvn_opts' delta_opts='$delta_opts' ivector_dim='$ivector_dim'"
fi

###### PREPARE FEATURE PIPELINE ######
# read the features,
feats_tr="ark:copy-feats scp:$dir/train.scp ark:- |"
feats_cv="ark:copy-feats scp:$dir/cv.scp ark:- |"

###### INITIALIZE THE NNET ######
echo 
echo "# NN-INITIALIZATION"
if [ ! -z $nnet_init ]; then
  echo "# using pre-initialized network '$nnet_init'"
elif [ ! -z $nnet_proto ]; then
  echo "# initializing NN from prototype '$nnet_proto'";
  nnet_init=$dir/nnet.init; log=$dir/log/nnet_initialize.log
  nnet-initialize --seed=$seed $nnet_proto $nnet_init
else 
  echo "# getting input/output dims :"
  # input-dim,
  #get_dim_from=$feature_transform
  #[ ! -z "$dbn" ] && get_dim_from="nnet-concat $feature_transform '$dbn' -|"
  #num_fea=$(feat-to-dim "$feats_tr nnet-forward \"$get_dim_from\" ark:- ark:- |" -)
  num_fea=$(feat-to-dim "$feats_tr" -)

  # output-dim,
  [ -z $num_tgt ] && \
    num_tgt=$(hmm-info --print-args=false $alidir/final.mdl | grep pdfs | awk '{ print $NF }')

  # make network prototype,
  nnet_proto=$dir/nnet.proto
  echo "# genrating network prototype $nnet_proto"
  case "$network_type" in
    dnn)
      utils/nnet/make_nnet_proto.py $proto_opts \
        ${bn_dim:+ --bottleneck-dim=$bn_dim} \
        $num_fea $num_tgt $hid_layers $hid_dim >$nnet_proto
      ;;
    cnn1d)
      delta_order=$([ -z $delta_opts ] && echo "0" || { echo $delta_opts | tr ' ' '\n' | grep "delta[-_]order" | sed 's:^.*=::'; })
      echo "Debug : $delta_opts, delta_order $delta_order"
      utils/nnet/make_cnn_proto.py $cnn_proto_opts \
        --splice=$splice --delta-order=$delta_order --dir=$dir \
        $num_fea >$nnet_proto
      cnn_fea=$(cat $nnet_proto | grep -v '^$' | tail -n1 | awk '{ print $5; }')
      utils/nnet/make_nnet_proto.py $proto_opts \
        --no-proto-head --no-smaller-input-weights \
        ${bn_dim:+ --bottleneck-dim=$bn_dim} \
        "$cnn_fea" $num_tgt $hid_layers $hid_dim >>$nnet_proto
      ;;
    cnn2d) 
      delta_order=$([ -z $delta_opts ] && echo "0" || { echo $delta_opts | tr ' ' '\n' | grep "delta[-_]order" | sed 's:^.*=::'; })
      echo "Debug : $delta_opts, delta_order $delta_order"
      utils/nnet/make_cnn2d_proto.py $cnn_proto_opts \
        --splice=$splice --delta-order=$delta_order --dir=$dir \
        $num_fea >$nnet_proto
      cnn_fea=$(cat $nnet_proto | grep -v '^$' | tail -n1 | awk '{ print $5; }')
      utils/nnet/make_nnet_proto.py $proto_opts \
        --no-proto-head --no-smaller-input-weights \
        ${bn_dim:+ --bottleneck-dim=$bn_dim} \
        "$cnn_fea" $num_tgt $hid_layers $hid_dim >>$nnet_proto
      ;;
    lstm)
      utils/nnet/make_lstm_proto.py $proto_opts \
        $num_fea $num_tgt >$nnet_proto
      ;;
    blstm)
      utils/nnet/make_blstm_proto.py $proto_opts \
        $num_fea $num_tgt >$nnet_proto
      ;; 
    *) echo "Unknown : --network-type $network_type" && exit 1;
  esac

  # initialize,
  nnet_init=$dir/nnet.init
  echo "# initializing the NN '$nnet_proto' -> '$nnet_init'"
  nnet-initialize --seed=$seed $nnet_proto $nnet_init

  # optionally prepend dbn to the initialization,
  if [ ! -z "$dbn" ]; then
    nnet_init_old=$nnet_init; nnet_init=$dir/nnet_dbn_dnn.init
    nnet-concat "$dbn" $nnet_init_old $nnet_init
  fi
fi


###### TRAIN ######
echo
echo "# RUNNING THE NN-TRAINING SCHEDULER"
steps/nnet/train_scheduler.sh \
  ${scheduler_opts} \
  ${train_tool:+ --train-tool "$train_tool"} \
  ${train_tool_opts:+ --train-tool-opts "$train_tool_opts"} \
  --learn-rate $learn_rate \
  ${frame_weights:+ --frame-weights "$frame_weights"} \
  ${utt_weights:+ --utt-weights "$utt_weights"} \
  ${config:+ --config $config} \
  $nnet_init "$feats_tr" "$feats_cv" "$labels_tr" "$labels_cv" $dir

echo "$0: Successfuly finished. '$dir'"

sleep 3
exit 0
