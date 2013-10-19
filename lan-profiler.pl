#!/usr/bin/env perl

use strict;
use warnings;
use Time::HiRes;
use lib 'inc';
use IO::Interface::Simple;
use Net::Netmask;
use Net::Ping;

my @if_list = IO::Interface::Simple->interfaces;
my $ping = Net::Ping->new('tcp', 0.05);
$ping->hires();

if (scalar(@if_list) => 1) {
	print "Available interfaces:\n";
	for my $if (@if_list) {
		print "\t$if (", $if->address, ")\n" if $if->address;
	}
	print "\n";
}
else {
	print "No interface found. Exiting.\n";
	exit 0;
}

for my $if (@if_list) {
	# Skipping loopback interface
	if ($if eq 'lo') {
		print "Skipping loopback interface.\n\n";
		next;
	}
	# Skipping VirtualBox virtual interfaces
	elsif ($if =~ m/vbox/) {
		print "Skipping VirtualBox virtual interfaces.\n\n";
		next;
	}
	
	print "Scanning $if.\n";
	my $address = $if->address;
	my $netmask = $if->netmask;
	my @lan;
	
	my $block = new2 Net::Netmask ($address, $netmask);
	
	if (defined $block) {
		@lan = $block->enumerate;
	}
	else {
		print "Invalid netmask for $if. Skipping.\n";
		next;
	}
	
	for my $host (@lan) {
		print "$host is alive.\n" if $ping->ping($host);
	}
	
	print "\n";
}

exit 0;
