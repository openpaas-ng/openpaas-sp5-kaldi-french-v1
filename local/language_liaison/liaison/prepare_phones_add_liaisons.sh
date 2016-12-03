tmpdir=$1
dir=$2

for x in tt zz vv nn; do
  len=$(wc -l < $dir/phones.txt);
  echo "${x}_L" $len >> $dir/phones.txt
  echo "${x}_L" >> $dir/phones/nonsilence.txt
  sed -i "s/shared split ${x}_B ${x}_E ${x}_I ${x}_S/shared split ${x}_B ${x}_E ${x}_I ${x}_S ${x}_L/g" $dir/phones/roots.txt
  sed -i "s/${x}_B ${x}_E ${x}_I ${x}_S/${x}_B ${x}_E ${x}_I ${x}_S ${x}_L/g" $dir/phones/sets.txt
  echo "${x}_L liaison" >> $dir/phones/word_boundary.txt
  sed -i "s/${x} ${x}_B ${x}_E ${x}_I ${x}_S/${x} ${x}_B ${x}_E ${x}_I ${x}_S ${x}_L/g" $tmpdir/phone_map.txt
done
