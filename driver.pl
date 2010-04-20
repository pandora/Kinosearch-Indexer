#!/usr/bin/perl

# Running this driver script will create an inverted index. It will
# also perform a set of searches against the index.

# Please remember to modify the two constants below to suit your environment.

use strict;
use warnings;
use lib './';

use Indexer;
use Readonly;

Readonly my $INDEX_LOCATION   => '/tmp/idx';

# Entire file obtainable from http://library.hud.ac.uk/data/usagedata/circulation_data.xml.zip
# Last accessed Tue 20 Apr, 2010. Data available under the CCO
# licence. A condensed version is distributed with this code.
Readonly my $CIRCULATION_DATA => './circulation_data_small.xml';

my $indexer = Indexer->new(
    source  => $CIRCULATION_DATA,
    idx_loc => $INDEX_LOCATION,
    verbose => 1,
);
$indexer->build_from_file;
