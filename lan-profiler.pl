#!/usr/bin/env perl

# Core modules
use strict;
use warnings;
use Time::HiRes;
use IO::Handle;
use lib 'inc';

# From CPAN in 'inc' subfolder
use Net::Netmask;
use Net::Ping;
use HTTP::Tiny;

# Setting autoflush for STDOUT and STDERR
autoflush STDOUT 1;
autoflush STDERR 1;

sub getVendor {
	my $mac = $_[0];
	my $response = HTTP::Tiny->new->get('http://api.macvendors.com/' . $mac);
	
	return $response->{content};
}

# Retrieving list of interfaces
my @if_list = (`/sbin/ifconfig -a` =~ m/^(\w+)\b/mg);

# Building hashes from the list
my @if_h;
for my $if (@if_list) {
	my $new_if = {};
	my $if_info = `/sbin/ifconfig $if`;
	$new_if->{name} = $if;
	($new_if->{address}) = ($if_info =~ m/inet\s(?:addr:){0,1}(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/);
	($new_if->{netmask}) = $if_info =~ m/(?:Mask:|netmask\s)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/;
	push @if_h, $new_if;
}

my $ping = Net::Ping->new('tcp', 0.05);
$ping->hires();

if (scalar(@if_h) => 1) {
	print "Available interfaces:\n";
	for my $if (@if_h) {
		print "\t", $if->{name}, " (", $if->{address}, ")\n" if $if->{address};
	}
	print "\n";
}
else {
	print "No interface found. Exiting.\n";
	exit 0;
}

for my $if (@if_h) {
	# Skipping loopback interface
	if ($if->{name} eq 'lo') {
		print "Skipping loopback interface.\n\n";
		next;
	}
	# Skipping VirtualBox virtual interfaces
	elsif ($if->{name} =~ m/vbox/) {
		print "Skipping VirtualBox virtual interfaces.\n\n";
		next;
	}
	
	print "Scanning $if->{name}.\n";
	my $address = $if->{address};
	my $netmask = $if->{netmask};
	my @lan;
	
	my $block = new2 Net::Netmask ($address, $netmask);
	
	if (defined $block) {
		@lan = $block->enumerate;
	}
	else {
		print "Invalid netmask for $if->{name}. Skipping.\n";
		next;
	}
	
	# Looking for arp binary file
	my $arp_b;
	if (-f "/sbin/arp") {
		$arp_b = '/sbin/arp';
	}
	elsif (-f '/usr/sbin/arp') {
		$arp_b = '/usr/sbin/arp';
	}
	else {
		print STDERR "Command arp not found.\n";
		exit 1;
	}		
	
	for my $host (@lan) {
		if ($ping->ping($host)) {
			print "$host";
			my $arp_cache = `$arp_b -a $host -i $if->{name}`;
			if ($arp_cache !~ m/no match found/) {
				my $mac = (split(' ', $arp_cache))[3];
				print "\t", $mac;
				my $vendor = getVendor($mac);
				print "\t", $vendor;
			}
			print "\n";
		}
	}
	
	print "\n";
}

exit 0;
