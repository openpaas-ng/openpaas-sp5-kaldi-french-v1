#!/usr/bin/env perl
use warnings; #sed replacement for -w perl parameter

# Makes lexicon while taking into account liaison for French language. 
# Has two loop states : acceptor (words starting with vowels) and normal (other words)

# Difference with version 1:
# Has two liaison generators : Z and T sounds (words ending with z,x,s,t)
# Has two silence state : generator endings and normal endings

$liaison_prob = 0.5; #can change this
$half_cost = -log(0.5); #split between acceptor and normal

$pron_probs = 0;
if ($ARGV[0] eq "--pron-probs") {
  $pron_probs = 1;
  shift @ARGV;
}

if (@ARGV != 1 && @ARGV != 3 && @ARGV != 4) {
  print STDERR
    "Usage: make_lexicon_fst_liaison.pl [--pron-probs] lexicon.txt [silprob silphone [sil_disambig_sym]] >lexiconfst.txt
Creates a lexicon FST that transduces phones to words, and may allow optional silence.
Note: ordinarily, each line of lexicon.txt is: word phone1 phone2 ... phoneN; if the --pron-probs option is
used, each line is: word pronunciation-probability phone1 phone2 ... phoneN.  The probability 'prob' will
typically be between zero and one, and note that it's generally helpful to normalize so the largest one
for each word is 1.0, but this is your responsibility.  The silence disambiguation symbol, e.g. something
like #5, is used only when creating a lexicon with disambiguation symbols, e.g. L_disambig.fst, and was
introduced to fix a particular case of non-determinism of decoding graphs.\n";
  exit(1);
}

$lexfn = shift @ARGV;
if (@ARGV == 0) {
  $silprob = 0.0;
} elsif (@ARGV == 2) {
  ($silprob,$silphone) = @ARGV;
} else {
  ($silprob,$silphone,$sildisambig) = @ARGV;
}
if ($silprob != 0.0) {
  $silprob < 1.0 || die "Sil prob cannot be >= 1.0";
  $silcost = -log($silprob);
  $halfsilcost = -log($silprob / 2.0); #needed to split acceptor and normal
  $halfnosilcost = -log((1.0 - $silprob) / 2.0);#needed to split acceptor and normal
} 


open(L, "<$lexfn") || die "Error opening lexicon $lexfn";
if ( $silprob == 0.0 ) { # No optional silences: just have one (loop+final) state which is numbered zero.
  $loopstate = 0;
  $nextstate = 1;               # next unallocated state.
  while (<L>) {
    @A = split(" ", $_);
    @A == 0 && die "Empty lexicon line.";
    foreach $a (@A) {
      if ($a eq "<eps>") {
        die "Bad lexicon line $_ (<eps> is forbidden)";
      }
    }
    $w = shift @A;
    if (! $pron_probs) {
      $pron_cost = 0.0;
    } else {
      $pron_prob = shift @A;
      if (! defined $pron_prob || !($pron_prob > 0.0 && $pron_prob <= 1.0)) {
        die "Bad pronunciation probability in line $_";
      }
      $pron_cost = -log($pron_prob);
    }
    if ($pron_cost != 0.0) { $pron_cost_string = "\t$pron_cost"; } else { $pron_cost_string = ""; }

    $s = $loopstate;
    $word_or_eps = $w;
    while (@A > 0) {
      $p = shift @A;
      if (@A > 0) {
        $ns = $nextstate++;
      } else {
        $ns = $loopstate;
      }
      print "$s\t$ns\t$p\t$word_or_eps$pron_cost_string\n";
      $word_or_eps = "<eps>";
      $pron_cost_string = ""; # so we only print it on the first arc of the word.
      $s = $ns;
    }
  }
  print "$loopstate\t0\n";      # final-cost.
} else {
  $startstate = 0;
  $acceptorloopstate = 1; #vowels
  $normalloopstate = 2; #nonvowels
  $silstate = 3;   # state from where we go to loopstate after emitting silence.
  $prezstate = 4; #4->5 with sil
  $zliaisonstate = 5; # 5->1 with inputlabel zz_L
  $pretstate = 6;
  $tliaisonstate = 7; # same for t

  $gensilstate = 8; #sil state to which generators go (to handle diff acc/norm proba)
  $gennormalcost = -log($silprob / ($silprob*(2-$liaison_prob))); #normalizing to 1
  $genacceptorcost = -log(($silprob*(1-$liaison_prob)) / ($silprob*(2-$liaison_prob)));

  print "$startstate\t$acceptorloopstate\t<eps>\t<eps>\t$halfnosilcost\n"; # no silence.
  print "$startstate\t$normalloopstate\t<eps>\t<eps>\t$halfnosilcost\n"; # no silence.
  print "$zliaisonstate\t$acceptorloopstate\tzz_L\t<eps>\n"; #z liaison
  print "$tliaisonstate\t$acceptorloopstate\ttt_L\t<eps>\n"; #t liaison
  if (!defined $sildisambig) {
    print "$startstate\t$acceptorloopstate\t$silphone\t<eps>\t$halfsilcost\n"; # silence.
    print "$startstate\t$normalloopstate\t$silphone\t<eps>\t$halfsilcost\n"; # silence.
    print "$silstate\t$acceptorloopstate\t$silphone\t<eps>\t$half_cost\n"; #half prob of each
    print "$silstate\t$normalloopstate\t$silphone\t<eps>\t$half_cost\n"; 
    print "$prezstate\t$zliaisonstate\t$silphone\t<eps>\n"; 
    print "$pretstate\t$tliaisonstate\t$silphone\t<eps>\n";
    print "$gensilstate\t$acceptorloopstate\t$silphone\t<eps>\t$genacceptorcost\n";
    print "$gensilstate\t$normalloopstate\t$silphone\t<eps>\t$gennormalcost\n";
    $nextstate = 9;
  } else {
    $disambigstate = 9;
    $disambigliaisonzstate = 10;
    $disambigliaisontstate = 11;
    $gendisambigstate = 12;
    $nextstate = 13;
    print "$startstate\t$disambigstate\t$silphone\t<eps>\t$silcost\n"; # silence.
    print "$silstate\t$disambigstate\t$silphone\t<eps>\n"; # no cost.
    print "$disambigstate\t$acceptorloopstate\t$sildisambig\t<eps>\t$half_cost\n"; # sil disambig 
    print "$disambigstate\t$normalloopstate\t$sildisambig\t<eps>\t$half_cost\n"; # sil disambig 

    print "$gensilstate\t$gendisambigstate\t$silphone\t<eps>\n"; # no cost.
    print "$gendisambigstate\t$acceptorloopstate\t$sildisambig\t<eps>\t$genacceptorcost\n"; 
    print "$gendisambigstate\t$normalloopstate\t$sildisambig\t<eps>\t$gennormalcost\n"; 

    print "$prezstate\t$disambigliaisonzstate\t$silphone\t<eps>\n"; 
    print "$pretstate\t$disambigliaisontstate\t$silphone\t<eps>\n"; 
    print "$disambigliaisonzstate\t$zliaisonstate\t$sildisambig\t<eps>\n";
    print "$disambigliaisontstate\t$tliaisonstate\t$sildisambig\t<eps>\n";

  }
  while (<L>) {
    @A = split(" ", $_);
    $w = shift @A;
    if (! $pron_probs) {
      $pron_cost = 0.0;
    } else {
      $pron_prob = shift @A;
      if (! defined $pron_prob || !($pron_prob > 0.0 && $pron_prob <= 1.0)) {
        die "Bad pronunciation probability in line $_";
      }
      $pron_cost = -log($pron_prob);
    }
    if ($pron_cost != 0.0) { $pron_cost_string = "\t$pron_cost"; } else { $pron_cost_string = ""; }

    $word_or_eps = $w;

    $p = shift @A;
    $w1 = substr( $p, 0, 2 ); #first two letters
    unshift @A, $p;
    my @acceptorarray=("aa", "ai", "an", "au", "ee", "ei", "eu", "ii", "in", "oe", "on", "oo", "ou", "un", "uu", "uy"); #acceptor phonemes
    my %acceptorhash = map { $_, 1 } @acceptorarray; #map them to 1

    if( $acceptorhash{ $w1 } ){
      $s = $acceptorloopstate;
    } else {
      $s = $normalloopstate;
    }

    $generator=0;
    if (@A > 1){ #not singleton
      $p0 = substr( $w, -1, 1 ); #last letter of word
      my @generatorarray=("s", "z", "x", "t"); #generator if it's a s, z, x, or t
      #improving model: adding n, r, p (but less common)
      my %generatorhash = map { $_, 1 } @generatorarray; #map them to 1
      $p1 = substr($A[-1], 0, 2); #last phoneme of word
      if( $generatorhash{ $p0 } && !($p1 eq "tt") && !($p1 eq "zz")){
        $generator=1;
      }
    }

    while (@A > 0) {
      $p = shift @A;
      if (@A > 0) {
        $ns = $nextstate++;
	print "$s\t$ns\t$p\t$word_or_eps$pron_cost_string\n";
        $word_or_eps = "<eps>";
        $pron_cost_string = ""; $pron_cost = 0.0; # so we only print it the 1st time.
        $s = $ns;
      } elsif (!defined($silphone) || $p ne $silphone) {
	# last phone of generators
        if( $generator ){
	  $acceptor_noliaison_nosilcost=-log((1-$silprob)*(1-$liaison_prob)/2.0);
	  print "$s\t$acceptorloopstate\t$p\t$word_or_eps\t$acceptor_noliaison_nosilcost\n";
	  print "$s\t$normalloopstate\t$p\t$word_or_eps\t$halfnosilcost\n";

	  $gen_silcost=-log($silprob*(2-$liaison_prob)/2.0);
	  print "$s\t$gensilstate\t$p\t$word_or_eps\t$gen_silcost\n";

	  $acceptor_liaison_nosilcost=-log((1-$silprob)*$liaison_prob/2.0);
	  $acceptor_liaison_silcost=-log($silprob*$liaison_prob/2.0);
	  if( $p0 eq "t" ){
	    print "$s\t$tliaisonstate\t$p\t<eps>\t$acceptor_liaison_nosilcost\n";
            print "$s\t$pretstate\t$p\t<eps>\t$acceptor_liaison_silcost\n";
	  } else{
	    print "$s\t$zliaisonstate\t$p\t<eps>\t$acceptor_liaison_nosilcost\n";
	    print "$s\t$prezstate\t$p\t<eps>\t$acceptor_liaison_silcost\n";
	  }
      } else {
          # last phone of nongenerators
          print "$s\t$acceptorloopstate\t$p\t$word_or_eps\t$halfnosilcost\n";
          print "$s\t$normalloopstate\t$p\t$word_or_eps\t$halfnosilcost\n";
          print "$s\t$silstate\t$p\t$word_or_eps\t$silcost\n";
        }
      } else {
        # Since no silent phone or $p is $silphone, ignore liaison
	# no point putting opt-sil after silence word.
        print "$s\t$normalloopstate\t$p\t$word_or_eps$pron_cost_string\n";
        print "$s\t$acceptorloopstate\t$p\t$word_or_eps$pron_cost_string\n";
      }
    }
  }
  print "$acceptorloopstate\t0\n";      # final-cost.
  print "$normalloopstate\t0\n";      # final-cost.
}
