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
		if ($ping->ping($host)) {
			print "$host";
			my $arp_cache = `/sbin/arp -a $host -i $if`;
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
