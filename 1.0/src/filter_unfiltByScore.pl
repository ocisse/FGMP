#!/usr/bin/perl -w


use strict; 
use feature 'say';

# System Modules
use IO::All;
use Data::Dumper; 
use Scalar::Util qw(looks_like_number);
use Getopt::Long;

die "

# This scipt takes a hmmsearch output ( domtbl format) file, a profile thresholds file and 
# a file containing the name of 245 fgmp markers ( one per line)
# and give a text file containing the name of the maker and the best scoring
# protein ( one per line)


filter_unfiltByScore.pl < hmmseach > < profiles_cutoff.tbl > < 245 FGMP> > file

example: 
perl filter_unfiltByScore.pl test.2.hmmseach profiles_cutoff.tbl 245Markers.txt --cutoff 0.7

options
-v		verbose 
--cutoff 	alternative cutoff
" unless (@ARGV > 2); 

my $completeCutoff  = '0.7';
GetOptions(
	    "cutoff=f" => \$completeCutoff
);

my ($hmmsearchOut,$cutoff,$consMarkers) = @ARGV; 

# ---------------------------------------------- #
#
# Check if the files exist
#
# ---------------------------------------------- #
if (!(-e "$hmmsearchOut")){
	say "File does not exist: $hmmsearchOut";
	exit(1);
}

if (!(-e "$cutoff")){
	say "File does not exist: $cutoff";
	exit(1);
}

if (!(-e"$consMarkers")){
	say "File does not exist: $consMarkers";
	exit(1);
}

# ---------------------------------------------- #
# parse cutoff file and record model score cutoff 
# and length
# ---------------------------------------------- #

# record hmm score and the length of the original
# untrimmed alignment
&report("...LOADING PROFILES DATA");

my ($hmmcutoff,$hmmAlgnlen,$hmmRatio) = parseCutoffData($cutoff);
my %hmmcutoff = %$hmmcutoff;
my %hmmAlgnlen = %$hmmAlgnlen;
my %hmmRatio = %$hmmRatio;

# load the name of 245 markers
&report("...LOADING 245 markers data"); 

my %markers = load("$consMarkers");  

# load sequence length 
&report("...LOADING SEQS LENGTH AND MODELS TO SEARCH"); 

my ($seqLen, $hmmName) = extractSeqLenAndmodelNames($hmmsearchOut);
my %seqLen = %$seqLen;
my %hmmName = %$hmmName;

# ---------------------------------------------- #
# retrieve the best protein for each model
# based on score
# ---------------------------------------------- # 
 &report("...ANALZING HMMSEARCH OUTPUT");

# containers
my %seq2scoreG = ();
my %seq2model = (); 
my %significantmodel = ();

my $model = ""; 
foreach $model (keys %hmmName){
	
	# how many proteins map against this model
	# key = seq, value = score
	my %seq2scorel = extractSeqForThismodel($model,$hmmsearchOut);
	
	# now pick for this model the best candidate
	my $cand = ""; 
	my $scoretmp = 10;
	my $bestCand = "";
	my $empty = ""; 
	
	foreach $cand (keys %seq2scorel){
		unless ($seq2scorel{$cand} eq 'NOT FOUND') { # skip those models without hits
			
			# check that the best seq pass the filtering cuoff
			if ($seq2scorel{$cand} >= ($hmmcutoff{$model} * 0.2)){ # 0.4 is an empirically determined value (seems to work best for Anid and Ncra
		
        
			# I catch model with significnat hits in the preds
		 	
			if ($markers{$model}){
				 $significantmodel{$model} = $model;
			#	say "TES1\t$markers{$model} is a FGMP markers";
			} else {
			#	say "TEST2\t$model is not part of FGMP conserved markers";
			}


		# now iterate to pick the best seq based on score
				unless ($seq2scorel{$cand} < $scoretmp){
					$scoretmp = $seq2scorel{$cand};
					$bestCand = $cand;
					}
			} else {
				# do something the seqs that failed to pass the score cutoff
			}
		}
	} 
	$seq2model{$bestCand} = $model if ($bestCand ne $empty);
	$seq2scoreG{$bestCand} = $scoretmp if ($scoretmp ne $empty); # record the score of those seq
}

my $fgmpMarkers = keys %significantmodel;

# catch missing markers
my %missingFGMPmarkers = (); 

my $m = "";
foreach $m (keys %markers){
	unless ($significantmodel{$m}){
		$missingFGMPmarkers{$m} = $m;
	}
}

# ---------------------------------------------- #
# EXTRACT ALN LENGTH FOR BEST CANDIDATES
# ---------------------------------------------- #
&report("...EXTRACTING ALN LENGHT FOR THE BEST CANDIDATE");
my %seq2alnLen = (); 
my $el = "";
foreach $el (keys %seq2model){
	my $alnLength = extractLenAln($el,$seq2model{$el},$hmmsearchOut);
	$seq2alnLen{$el} = $alnLength;
}

# ---------------------------------------------- #
# TRACK ABBERANT PROTEINS
# ---------------------------------------------- #
&report("...TRACKING ABBERANT PROTEINS");

# key = seq xxx = value = AB|NORM
my ($abberantProteins,$countAbb) = isAbberrant(\%seqLen,\%hmmAlgnlen,\%seq2model); 
my %abberantProteins = %$abberantProteins;

# ---------------------------------------------- #
# check that protein cover at least 70% of the 
# alignment (i.e. the original untrimmed aligment
# used to built the profil)
# ---------------------------------------------- #
 &report("...COMPLETION SUTFF");
my %goodPreds = (); 
my $complete = 0; 
my $partial = 0;

# counters
my ($v) = "";
my $count = 1;

my $total = scalar (keys %seq2model);

# my cutoffs
#my $completeCutoff = '0.7'; 

# at this stage of the model present in this hash have a sequence that has passed the score filter
# only the best sequence per model should arrive here

my $logfull  = "# SEQ\tMODEL\tSTATUS\tCOMPLETNESS\tCONS\n"; 
   $logfull .= "# ------------------------------------------------------------ #\n";

foreach $v (keys %seq2model){
	&report("----> JOBS DONE $count / $total"); 
	my $threshold = ($hmmAlgnlen{$seq2model{$v}} * $completeCutoff); 
	
	# check that the length of the sequence is at least 70% that of the untrimmed alignment used to build the profil
	if ($seq2alnLen{$v} >= $threshold){
		$complete++;
		# say "$threshold is", looks_like_number($threshold) ? '': ' not', " a number";

		# check if that is one of the 245 fgmp
		if ($significantmodel{$seq2model{$v}}){
			$logfull .="$v\t$seq2model{$v}\tCOMPLETE\tFGMP\t$abberantProteins{$v}\t$hmmRatio{$seq2model{$v}}\n";
#			$fgmpMarkers++;
		} else {
		 	 $logfull .="$v\t$seq2model{$v}\tCOMPLETE\tXXXX\t$abberantProteins{$v}\t$hmmRatio{$seq2model{$v}}\n";

		}
		
	} elsif ($seq2alnLen{$v} <  $threshold){
		if ($significantmodel{$seq2model{$v}}){
			$logfull .="$v\t$seq2model{$v}\tPARTIAL\tFGMP\t$abberantProteins{$v}\t$hmmRatio{$seq2model{$v}}\n";
#			$fgmpMarkers++;
		    } else {
			$logfull .="$v\t$seq2model{$v}\tPARTIAL\tXXXX\t$abberantProteins{$v}\t$hmmRatio{$seq2model{$v}}\n";
		}
		$partial++;
	} else {
		#warn"hey don't know what going on here\n";

	}
	$count++;
}

&report("DONE!");

&report("PRINTING FULL REPORT");
io("$hmmsearchOut.full_report")->write($logfull);

&report("PRINTING SUMMARY REPORT");
my $totalUnfilteredPreds = keys %seqLen;
my $totalSeq  = keys %seq2model;
my $totalFgmp = scalar (keys %markers);
my $completness = sprintf("%.1f",(($fgmpMarkers / $totalFgmp) * 100));
my $missingFGMPmarkers = scalar %missingFGMPmarkers;


# printing report 
	my $logsum .= "| ---------------------------------------------------------- |\n";
	   $logsum .= "|\tSUMMARY STATISTICS\n";
           $logsum .= "| ---------------------------------------------------------- |\n";
	   $logsum .= "|\tTOTAL NUM OF PREDS ANALYZED:\t$totalUnfilteredPreds\n";
	   $logsum .= "|\tNo. BEST FILTERED PREDS:\t$totalSeq\n";
	   $logsum .= "|\tNUM OF MARKERS COMPLETE:\t$complete\n";
	   $logsum .= "|\tNUM OF MARKERS PARTIAL:\t$partial\n";
	   $logsum .= "|\tNUM OF ABBERANT PROTEINS:\t$countAbb\n";
	   $logsum .= "| ---------------------------------------------------------- |\n";
	   $logsum .= "|\tSTATUS\n";
	   $logsum .= "| ---------------------------------------------------------- |\n";   
	   $logsum .= "|\tNUM OF FGMP COMPLETENESS MARKERS:\t$fgmpMarkers\n";
	   $logsum .= "|\tEstimate completeness:\t$completness (%)\n";
	   $logsum .= "| ---------------------------------------------------------- |\n";
	   $logsum .= "|\t### MISSING MARKERS\n\n";   
	
	   foreach my $mis (keys %missingFGMPmarkers){
			$logsum .="|\t$mis\n";
	   }    
	   $logsum .= "| ---------------------------------------------------------- |\n\n";
	   $logsum .= "| These results are based on the set of genes selected by OHC & JES #\n\n";
	   $logsum .= "| Key:\n";
	   $logsum .= "| Prots completeness = 245 conserved fungal genes\n";
	   $logsum .= "| \%compleness = percent of 245 FCGs in the dataset\n";
	   $logsum .= "|---------------------------------------------------------- |\n";
	  
	 io("$hmmsearchOut.summary_report")->write($logsum);


# -------------------------------- #
# subs
# -------------------------------- #
sub extractLenAln {
	my ($seqname, $modelname,$filehmmseach) = @_; 

	my $len = 0; 
	my $hse = io("$filehmmseach");
           $hse->autoclose(0); 
	   while(my $hseline = $hse->getline || $hse->getline){
	   chomp $hseline; 
		next if $hseline =~ m/^#/;
		if (($hseline =~ m/$seqname/) && ($hseline =~ m/$modelname/)){
			my @dat = split /\s+/, $hseline; 
			my ($envStart,$envEnd) = ($dat[19],$dat[20]);
			my $lenTmp = ($envEnd - $envStart) + 1;
			$len += $lenTmp;
		}	
	}
	return $len;
}
sub isAbberrant{
        my ($seqlen,$hmmlen,$seq2mod) = @_; 

        my %seqslen = %$seqlen;
	my %hmmlen = %$hmmlen; 
	my %seq2mod = %$seq2mod;

	my $abcount = 0;
	my %abb = (); 

	# the names of seqs 
	my @seqs = keys %seq2mod; 

	# find  
	#my $id = "";
	my $empty = "";
 
	foreach my $id (keys %seq2mod){
		if ($seqslen{$id} > ($hmmlen{$seq2mod{$id}} x 2)){
				$abb{$id} = 'ABERRANT';
				$abcount++;
			} else {
			$abb{$id} = 'NORMAL';
			}
	}
	return(\%abb,$abcount);	
}
sub extractSeqLenAndmodelNames {
	my ($inHmmseach) = @_; 

	my %h4 = (); 
	my %h5 = (); 

	my $inH = io("$inHmmseach"); 
	   $inH->autoclose(0); 
	   while (my $inL = $inH->getline || $inH->getline){
	   chomp $inL; 	
			next if $inL =~ m/^#/; 	
			my ($id,$len,$modelName) = $inL =~/(Seq_\d+)\s+\-\s+(\d+)\s+(OMA\d+)/;
			$h4{$id} = $len;
			$h5{$modelName} = 'x';	   			   
	   }
	return(\%h4,\%h5);
}

sub load {
	my ($data) = @_; 

	my %h1 = (); 

	my $in = io("$data");
	   $in->autoclose(0);
	   while ( my $ln = $in->getline || $in->getline){
	   chomp $ln; 
		my @dat1 = split /_/, $ln;	
		$h1{$dat1[0]} = $dat1[0];
	    }
	return (%h1);
}

sub extractSeqForThismodel {
	my ($mod,$hmmscanFile) = @_;

	my %h = (); 
	my $file = io("$hmmscanFile");
 	$file->autoclose(0); 
	while (my $f = $file->getline || $file->getline){
	chomp $f; 

	next if $f =~ m/^#/;
	if ($f =~ m/$mod/){
		my @inline = split /\s+/, $f;
		my ($seqname,$model,$score,$envStarfileenvEnd) = ($inline[0],$inline[3],$inline[7],$inline[19],$inline[20]);
		
		# becareful beacuse the header of translated CDS contains the name of OMA groups
		if ($model ~~ $mod){
			# the score of a given seq against a particular model does not change
		 	$h{$seqname} = $score;		
			}
		else {
			next;
		}
	    } 
	}
	my @found = keys %h;

	if (@found == 0){ # check if empty hash
		$h{$mod} = 'NOT FOUND';
		}
	return(%h);
}

sub parseCutoffData{
	my ($data) = @_; 

	my (%h1,%h2,%h3) = ();

	my $in = io("$data");
	$in->autoclose(0);
	while (my $line = $in->getline || $in->getline){
	chomp $line;
		my @dat = split /\t/, $line;
		
		$h1{$dat[0]} = $dat[2];	 # hmm score cutoff 
		$h2{$dat[0]} = $dat[3];  # untrim aln length used for hmm construction
		$h3{$dat[0]} = $dat[4];	 # cons ratio
	}
	return (\%h1,\%h2,\%h3);
}
sub report {
	my ($log) = @_;
	warn"--- LOG:\t$log\n";
}
