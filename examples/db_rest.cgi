#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use DBIx::Snug;
use DBIx::Snug::REST;
use DBIx::Snug::MySQL::InformationSchema::Tables;
use DBIx::Snug::MySQL::InformationSchema::Columns;
use Data::Dumper;

if ( $ARGV[0] && $ARGV[0] =~ m#/# ) {
	$ENV{PATH_INFO} = $ARGV[0];
}

my $dbh = DBI->connect( 'DBI:mysql:database=mysql', '', '' );
my $r = DBIx::Snug::REST->new( $dbh );

$r->run();

print "\n";

