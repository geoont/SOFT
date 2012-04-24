#!/usr/bin/env perl
#

#
# Creates a match file between two ontologies
#

use strict;
use Carp;

use FileHandle;
use Getopt::Long qw(:config no_ignore_case bundling auto_help auto_version);
use Pod::Usage;
use Data::Dumper;
use Text::Soundex;

use SOFT;

# options variables
my $v = 0;            # verbosity
my $man = 0; 
my $output = '';      # file name to save the matches 
my $only = [];     # list of entities to include
my $exclude = [];     # list of entities to exclude

# process command-line options
GetOptions( 
	'v|verbose+' => \$v, 
	'o|output=s' => \$output,
	'only=s@' => \$only, 
	'exclude=s@' => \$exclude, 
	'man' => \$man ) or pod2usage(2);
pod2usage(-exitstatus => 0, -verbose => 2, -output => \*STDERR ) if $man;
pod2usage(3) if @ARGV != 2;
#print $v, "\n";

# initialize recipe list
my @recipies = qw/exact soundex words_exact words_soundex/;

# create stop word lists
my %stop_words = map { $_ => 1 } qw/FACILITY FACILITIES REGION REGIONS/;

# load ontologies
my $softh1 = SOFT->new( { 'verbose' => $v } );
$softh1->parse_soft( $ARGV[0] );
$softh1->only( &expand( @$only ) ) if (@$only );
$softh1->exclude( &expand( @$exclude ) ) if (@$exclude );

my $softh2 = SOFT->new( { 'verbose' => $v } );
$softh2->parse_soft( $ARGV[1] );
$softh2->only( &expand( @$only ) ) if (@$only );
$softh2->exclude( &expand( @$exclude ) ) if (@$exclude );

# initialize match list
#   match list is a hash with "cat:from cat:to" as a key
#   each value is a hash { 'from' => $from, to => $to, 'match_recipies' => [recipies] }
my %matches = ();

# do matches on all pairs on entities in ontologies
foreach my $recipe (@recipies) {
	print "Match recipe: ".uc($recipe)." ... \n";
	my $mcount = 0;
	foreach my $from ($softh1->all()) {
		foreach my $to ($softh2->all()) {
			print "Matching $from to $to ..." if $v > 2;
			my $r = eval "match_$recipe( '$from', '$to' )";
			die "Match of $from to $to produced an error: $@" if $@;
			if ($r) {
				print " SUCCESS=$r\n" if $v > 2;

				# recording match 
				$mcount++;
				my $match = "$from $to";
				unless (exists $matches{$match}) {
					$matches{$match} = { 
						'from' => $from, 
						'to' => $to, 
						'matches' => { $recipe => $r } 
					};
				} else {
					$matches{$match}->{'matches'}->{$recipe} = $r;
				}
			} else {
				print " nope\n" if $v > 2;
			}
		}
	}
	print "$mcount matches found\n";
}

# save matches in a match file
unless ($output) {
	my ($f1) = ($ARGV[0] =~ m/([^\/]+)\.soft$/);
	my ($f2) = ($ARGV[1] =~ m/([^\/]+)\.soft$/);
	$output = "$f1-$f2-auto.match";
}
my $mh = new FileHandle ">$output" || die ">$output: $!";
print $mh "#\n# SOFT match file\n# matches between: $ARGV[0] => $ARGV[1]\n";
print $mh "# auto-generated by $0 on ".localtime()."\n#\n";

my $c = 0;
foreach (sort keys %matches) {
	my %rcps = (%{$matches{$_}->{'matches'}});
	print $mh 
		$matches{$_}->{'from'},
		" === ",
		$matches{$_}->{'to'},
		"\t# ",
		join( ', ', map { $_.'='.$rcps{$_} } keys %rcps ),
		"\n";
	$c++;
}

$mh->close();
print "$c matches saved in $output\n";

exit;

#
# Match recipes
#

sub match_exact {
	my($ent1, $ent2) = (@_);
	
	return uc $ent1 eq uc $ent2;
}

sub match_soundex {
	my($ent1, $ent2) = (@_);
	
	# get rid of types first
	my ($type1,$id1) = ( $ent1 =~ m/^(cat|inst):(\S+)$/o );
	my ($type2,$id2) = ( $ent2 =~ m/^(cat|inst):(\S+)$/o );
	
	return $type1 eq $type2 && soundex($id1) eq soundex($id2);
}

sub match_words_exact {
	my($ent1, $ent2) = (@_);
	
	# get rid of types first
	my ($type1,$id1) = ( $ent1 =~ m/^(cat|inst):(\S+)$/o );
	my ($type2,$id2) = ( $ent2 =~ m/^(cat|inst):(\S+)$/o );
	
	return undef unless $type1 eq $type2;
	
	# split ebtries into words
	$id1 =~ s/([a-z0-9])([A-Z])/$1 $2/go; # insert spaces in CamelCase words 
	$id1 =~ s/_/ /og;   # replace underscore with spaces
	$id2 =~ s/([a-z0-9])([A-Z])/$1 $2/go; # insert spaces in CamelCase words 
	$id2 =~ s/_/ /og;   # replace underscore with spaces
	
	my $r = 0;
	my $c = 0;
	foreach my $w1 (split '\s+', $id1) {
		next if exists $stop_words{uc $w1};
		foreach my $w2 (split '\s+', $id2) {
			next if exists $stop_words{uc $w2};
			$c++;
			$r++ if uc $w1 eq uc $w2;
		}	
	}
	
	return $r && 1.0 * $r/$c;
}

sub match_words_soundex {
	my($ent1, $ent2) = (@_);
	
	# get rid of types first
	my ($type1,$id1) = ( $ent1 =~ m/^(cat|inst):(\S+)$/o );
	my ($type2,$id2) = ( $ent2 =~ m/^(cat|inst):(\S+)$/o );
	
	return undef unless $type1 eq $type2;
	
	# split ebtries into words
	$id1 =~ s/([a-z0-9])([A-Z])/$1 $2/go; # insert spaces in CamelCase words 
	$id1 =~ s/_/ /og;   # replace underscore with spaces
	$id2 =~ s/([a-z0-9])([A-Z])/$1 $2/go; # insert spaces in CamelCase words 
	$id2 =~ s/_/ /og;   # replace underscore with spaces
	
	my $r = 0;
	my $c = 0;
	foreach my $w1 (split '\s+', $id1) {
		next if exists $stop_words{uc $w1};
		foreach my $w2 (split '\s+', $id2) {
			next if exists $stop_words{uc $w2};
			$c++;
			$r++ if soundex($w1) eq uc soundex($w2);
		}	
	}
	
	return $r && 1.0 * $r/$c;
}

# TODO: move this function into SOFT::Utils
# expands a list definition
sub expand {
	my @list = ();
	foreach (@_) {
		next unless $_;
		chomp;
		foreach (split ',') {
			if (m/^@(.+)/) {
				my $lh = new FileHandle( "<$1" ) || confess "Unable to open file '$1' for reading ($!)\n";
				push @list, map { &expand($_) } <$lh>;
				$lh->close();
			} else {
				push @list, $_;
			}
		}
	}
	return @list;
}


__END__

=head1 NAME

softmatch - Creates a match file between two soft files using various recipes

=head1 SYNOPSIS

soft2dot [options] <ontology1.soft> <ontology2.soft>  

 Options:
   --help,-h           brief help message
   --man               full documentation
   --verbose,-v+       increase verbosity
   --output=file.match specify output file name, '-' prints to stdout 
                       (default: ontology1-onotology2.match)
   --exclude=ent,@file exclude listed entities 
                       (can be a I<list>, applied to both ontologies)
   --only=ent,@file    include only listed entities 
                       (can be a I<list>, applied to both ontologies)

 Conventions:
   <list>              list items should be separated with commas, items
                       starting with @ will be interpreted as names of
                       files which contain elements on each lines (files 
                       can be nested)
                       
=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and match the entities using varios recipes.

=cut

