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

# Setting autoflush for STDOUT
autoflush STDOUT 1;

##
# These functions have been taken from Net::MAC::Vendor by
# Brian D Foy.
##
sub extract_oui_from_html {
	my $html = shift;
	my $lookup_mac = shift;

	$html =~ s/<pre>.*?$lookup_mac/<pre>$lookup_mac/is;

	# sometimes the HTML returns more than one OUI because
	# IEEE has a problem parsing their own data when they
	# have private blocks
	my( $ouis ) = $html =~ m|<pre>(.*?)</pre>|gs;
	return unless defined $ouis;
	$ouis =~ s/<\/?b>//gs; # remove bold around the OUI

	my @entries = split /\n\s*\n/, $ouis;
	return unless defined $entries[0];
	return $entries[0] unless defined $entries[1];

	my $result = $entries[0];

	foreach my $entry ( @entries ) {
		$entry =~ s/^\s+|\s+$//;
		my $found_mac = normalize_mac( substr $entry, 0, 8 );
		if( $found_mac eq $lookup_mac ) {
			$result = $entry;
			last;
			}
		}

	return $result;
}

sub parse_oui {
	my $oui = shift;
	return [] unless $oui;

	my @lines = map { s/^\s+//; $_ ? $_ : () } split /$/m, $oui;
	splice @lines, 1, 1, ();

	$lines[0] =~ s/\S+\s+\S+\s+//;
	return \@lines;
}
##
# End of code taken from Net::Mac::Vendor.
##

# Retrieving list of interfaces
my @if_list = (`/sbin/ifconfig -a` =~ m/^(\w+)\b/mg);

# Building hashes from the list
my @if_h;
for my $if (@if_list) {
	my $new_if = {};
	my $if_info = `/sbin/ifconfig $if`;
	$new_if->{name} = $if;
	($new_if->{address}) = ($if_info =~ m/inet addr:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/);
	($new_if->{netmask}) = $if_info =~ m/Mask:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/;
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
		print "Invalid netmask for $if. Skipping.\n";
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
				my $vendor_id = substr $mac, 0, 8;
				$vendor_id =~ tr/:/-/;
				my $response = HTTP::Tiny->new->get("http://standards.ieee.org/cgi-bin/ouisearch?$vendor_id");
				if (length $response->{content}) {
					my $vendor = parse_oui(extract_oui_from_html($response->{content}, $vendor_id));
					if ($vendor) {
						print "\t", $vendor->[0];
					}
				}
			}
			print "\n";
		}
	}
	
	print "\n";
}

exit 0;
