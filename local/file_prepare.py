#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This script appends utterances dumped out from XML to a Kaldi datadir

import sys, re
from xml.sax.saxutils import unescape

outfile = sys.argv[1]
text_file = open(outfile, 'a')

text = sys.argv[2]
ftext = open(text,'r')

lexicon = sys.argv[3]
flexicon = open(lexicon,'r')




#load the transcription
words = []
for m in ftext:
	m = m.strip()
	words.append(' '+m.lower()+' ')

#If lexicon file is specified, so apply the transformation to the text: make the text conforms to the lexicon file
#load the lexicon while modifying the text
lexicons = []
lexicons_ = []
for m in flexicon:
	ss = m.strip()
	lexicons_.append(ss)
	xx=re.sub(r'(_|-)',' ',ss)
	yy=re.sub(r"'","' ",xx)
	zz=re.sub(r'  ',' ',yy)
	lexicons.append(zz.strip())

for i in range(len(lexicons)):
	for j in range(len(words)):
		words[j] = words[j].replace(' '+lexicons[i]+' ',' '+lexicons_[i]+' ')
		words[j] = re.sub(r" +", " ", words[j].strip())


#Create segment, text, and utt2spk files
i=0
for m in words:
	print >> text_file, '%s' % (m)
text_file.close()


