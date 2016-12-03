export KALDI_ROOT='/opt/kaldi'
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

# VoxForge data will be stored in:
export DATA_ROOT="$KALDI_ROOT/egs/french/v1/french_speech"    # e.g. something like /media/secondary/voxforge

if [ -z $DATA_ROOT ]; then
  echo "You need to set \"DATA_ROOT\" variable in path.sh to point to the directory to host VoxForge's data"
  exit 1
fi


# SRILM
SRILM_ROOT=$KALDI_ROOT/tools/srilm
SRILM_PATH=$SRILM_ROOT/bin:$SRILM_ROOT/bin/i686-m64
export PATH=$PATH:$SRILM_PATH

#KaldiLM
export PATH=$PATH:$KALDI_ROOT/tools/kaldi_lm

#IRSTLM
export PATH=$PATH:$KALDI_ROOT/tools/irstlm/bin
export IRSTLM=$KALDI_ROOT/tools/irstlm



# Sequitur G2P executable
sequitur=$KALDI_ROOT/tools/sequitur/g2p.py
sequitur_path="$(dirname $sequitur)/lib/$PYTHON/site-packages"


# Make sure that MITLM shared libs are found by the dynamic linker/loader
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(pwd)/tools/mitlm-svn/lib
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:$KALDI_ROOT/tools/openfst/lib/
# Needed for "correct" sorting
export LC_ALL=C
