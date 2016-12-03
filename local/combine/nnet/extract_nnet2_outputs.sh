#!/bin/bash 

# Begin configuration section.
nj=4
cmd=run.pl
use_gpu=no
transform_dir=    # dir to find fMLLR transforms.
feat_type=
online_ivector_dir=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "usage: $0 [options] <tgt-data-dir> <src-data-dir> <nnet-dir> <log-dir> <abs-path-to-tgt-feat-dir>";
   echo "options: "
   echo "  --cmd 'queue.pl <queue opts>'   # how to run jobs."
   echo "  --nj <nj>                       # number of parallel jobs"
   echo "  --use-gpu (no|yes|optional)     # forwarding on GPU"
   echo "  --transform-dir <decoding-dir>  # directory of previous decoding" 
   exit 1;
fi

data=$1
srcdata=$2
nndir=$3
logdir=$4
bnfeadir=$5

######## CONFIGURATION


# copy the dataset metadata from srcdata.
mkdir -p $data $logdir $bnfeadir || exit 1;
utils/copy_data_dir.sh $srcdata $data; rm $data/{feats,cmvn}.scp 2>/dev/null

# make $bnfeadir an absolute pathname.
[ '/' != ${bnfeadir:0:1} ] && bnfeadir=$PWD/$bnfeadir

[ ! -z "$online_ivector_dir" ] && \
  extra_files="$online_ivector_dir/ivector_online.scp $online_ivector_dir/ivector_period"

for f in $srcdata/feats.scp $nndir/final.mdl $extra_files; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done



name=$(basename $srcdata)
sdata=$srcdata/split$nj
[[ -d $sdata && $srcdata/feats.scp -ot $sdata ]] || split_data.sh $srcdata $nj || exit 1;

cmvn_opts=`cat $nndir/cmvn_opts` || exit 1;


## Set up features.
if [ -z "$feat_type" ]; then
  if [ -f $nndir/final.mat ]; then feat_type=lda; else feat_type=raw; fi
  echo "$0: feature type is $feat_type"
fi

splice_opts=`cat $nndir/splice_opts 2>/dev/null`

case $feat_type in
  raw) feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |"
  if [ -f $nndir/delta_order ]; then
    delta_order=`cat $nndir/delta_order 2>/dev/null`
    feats="$feats add-deltas --delta-order=$delta_order ark:- ark:- |"
  fi
    ;;
  lda) feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $nndir/final.mat ark:- ark:- |"
    ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  [ ! -s $transform_dir/num_jobs ] && \
    echo "$0: expected $transform_dir/num_jobs to contain the number of jobs." && exit 1;
  nj_orig=$(cat $transform_dir/num_jobs)

  if [ $feat_type == "raw" ]; then trans=raw_trans;
  else trans=trans; fi
  if [ $feat_type == "lda" ] && \
    [ -f $transform_dir/../final.mat ] &&
    ! cmp $transform_dir/../final.mat $nndir/final.mat && \
    ! cmp $transform_dir/final.mat $nndir/final.mat; then
    echo "$0: LDA transforms differ between $nndir and $transform_dir"
    exit 1;
  fi
  if [ ! -f $transform_dir/$trans.1 ]; then
    echo "$0: expected $transform_dir/$trans.1 to exist (--transform-dir option)"
    exit 1;
  fi
  if [ $nj -ne $nj_orig ]; then
    # Copy the transforms into an archive with an index.
    for n in $(seq $nj_orig); do cat $transform_dir/$trans.$n; done | \
       copy-feats ark:- ark,scp:$data/$trans.ark,$data/$trans.scp || exit 1;
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk scp:$data/$trans.scp ark:- ark:- |"
  else
    # number of jobs matches with alignment dir.
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:$transform_dir/$trans.JOB ark:- ark:- |"
  fi
elif grep 'transform-feats --utt2spk' $nndir/log/train.1.log >&/dev/null; then
  echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
  echo "  but you are not providing the --transform-dir option in test time."
fi
##

# Run the forward pass,
$cmd JOB=1:$nj $logdir/make_feats.JOB.log \
nnet-am-compute --use-gpu=$use_gpu $nndir/final.mdl "$feats" ark:- \| \
copy-feats --compress=true ark:- ark,scp:$bnfeadir/raw_fea_$name.JOB.ark,$bnfeadir/raw_fea_$name.JOB.scp \
|| exit 1;

# concatenate the .scp files
for ((n=1; n<=nj; n++)); do
cat $bnfeadir/raw_fea_$name.$n.scp >> $data/feats.scp
done

# check sentence counts,
N0=$(cat $srcdata/feats.scp | wc -l) 
N1=$(cat $data/feats.scp | wc -l)
[[ "$N0" != "$N1" ]] && echo "$0: sentence-count mismatch, $srcdata $N0, $data $N1" && exit 1


echo "Succeeded creating MLP-BN features '$data'"

