#!/usr/bin/env perl

use strict;
use warnings;
use lib 'inc';
use IO::Interface::Simple;

my @if_list = IO::Interface::Simple->interfaces;

print 'Available interfaces: ';

for my $if (@if_list) {
	print $if, ' ';
}

print "\n";
