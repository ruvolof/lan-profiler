#!/usr/bin/env perl

use strict;
use warnings;
use Time::HiRes;
use IO::Handle;
use lib 'inc';

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

sub getIpTool {
	my $ip_tool = '/usr/sbin/ip';
	if (-e $ip_tool) {
		return $ip_tool;
	}
	die "Can't find $ip_tool.\n";
}

sub getArpTool {
	my $arp_tool = '/usr/sbin/arp';
	if (-e $arp_tool) {
		return $arp_tool;
	}
	die "Can't find $arp_tool.\n";
}

sub getInterfaceNames {
	my $ip_tool = getIpTool();
	my @interface_names;
	my @ip_tool_output = `$ip_tool a`;
	my @lines_with_interface_names = grep(/^\d.*mtu/, @ip_tool_output);
	for my $line (@lines_with_interface_names) {
		my $interface_name = (split /:/, $line)[1];
		$interface_name =~ s/^\s+//;
		push(@interface_names, $interface_name);
	}
	return @interface_names;
}

sub getInterfaceInfo {
	my $interface_name = $_[0];
	my $ip_tool = getIpTool();
	my @ip_tool_output = `$ip_tool a show $interface_name`;
	my @inet_line = grep(/^\s+inet\s/, @ip_tool_output);
	if (scalar @inet_line > 0) {
		my $interface_info_ref = {
			name => $interface_name,
			ipv4 => (split /\//, (split /\s+/, $inet_line[0])[2])[0],
			mask => (split /\//, (split /\s+/, $inet_line[0])[2])[1]
		};
		return $interface_info_ref;
	}
	return undef;
}

sub printInterfaceInfo {
	my $info_ref = $_[0];
	print "$info_ref->{name}:$info_ref->{ipv4}:$info_ref->{mask}\n";
}

sub main {
	my @interface_names = getInterfaceNames();
	my @interface_info_refs;
	for my $interface_name (@interface_names) {
		my $interface_info_ref = getInterfaceInfo($interface_name);
		if (defined $interface_info_ref) {
			push(@interface_info_refs, $interface_info_ref);
		}
	}
	if (scalar @interface_info_refs < 1) {
		print "No interfaces found.\n";
		exit 0;
	}

	my $ping = Net::Ping->new('tcp', 0.05);
	$ping->hires();

	print "Scanning networks.\n";
	for my $interface_info_ref (@interface_info_refs) {
		printInterfaceInfo($interface_info_ref);
		my $name = $interface_info_ref->{name};
		my $ipv4 = $interface_info_ref->{ipv4};
		my $mask = $interface_info_ref->{mask};
		if ($name eq 'lo') {
			print "Skipping loopback interface.\n";
			next;
		}
		
		my $block = Net::Netmask->new2("$ipv4/$mask");
		if (! defined $block) {
			print "Invalid netmask for $name:$ipv4/$mask.\n";
		}
		my @lan = $block->enumerate();
		my $arp_tool = getArpTool();
		for my $host (@lan) {
			if ($host eq $ipv4) {
				next;
			}
			if ($ping->ping($host)) {
				print "$host";
				my $arp_cache = `$arp_tool -a $host -i $name`;
				if ($arp_cache !~ m/no match found|incomplete/) {
					my $mac = (split ' ', $arp_cache)[3];
					print "\t$mac";
					my $vendor = getVendor($mac);
					print "\t", $vendor;
					sleep 2;
				}
				print "\n";
			}
		}
	}
	exit 0;
}

main();