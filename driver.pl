#!/usr/bin/perl

# Running this driver will create an inverted index using KinoSearch as well
# as perform searches against it.

# Please remember to modify the constants below to suit your environment.

use strict;
use warnings;
use lib './';

use Indexer;
use Readonly;

Readonly my $INDEX_LOCATION   => '/home/athomas/idx';

# File obtainable from http://library.hud.ac.uk/data/usagedata/circulation_data.xml.zip
# Last accessed Tue 20 Apr, 2010
Readonly my $CIRCULATION_DATA => '/home/athomas/circulation_data.xml';

my $indexer = Indexer->new(
    source  => $CIRCULATION_DATA,
    idx_loc => $INDEX_LOCATION,
    verbose => 1,
);
$indexer->build_from_file;
