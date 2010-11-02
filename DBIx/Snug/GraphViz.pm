package DBIx::Snug::GraphViz;

###########################################################################
#                                                                         #
# DBIx::Snug::GraphViz                                                    #
# Copyright 2008-2010, Albert P. Tobey <tobert@gmail.com>                 #
#                                                                         #
###########################################################################

=back

=head1 NAME

DBIx::Snug::GraphViz

=head1 DESCRIPTION

Generates a basic ER diagram based on currently-loaded modules that
subclass DBIx::Snug.

=head1 SYNOPSIS

=head1 METHODS

=over 4

=cut

use strict;
use warnings;
use Carp;
use Data::Dumper; # I use this a lot when debugging
use CGI qw(param);

require DBIx::Snug;
use File::Temp qw(tempfile);

=item new()

 my $g = DBIx::Snug::GraphViz->new();

=cut

sub new {
    my $type = shift;
    my( $dbh ) = grep { $_->isa('DBI::db') } @_;

    confess "An argument containing a DBI handle is required!"
        unless ( $dbh );

    return bless { dbh => $dbh }, $type;
}

=item dot()

Returns the raw graphviz definition.  Mainly useful for debugging.

=cut

sub dot {
    my $self = shift;

    my $dir = 'TB';
    my $gtype = 'digraph';
    my $arrow = '->';
    my $graphname = $0;
       $graphname =~ s/\W//g;

    if ( my $pdir = param('rankdir') ) {
        if ( $pdir =~ /^(TB|LR|BT|RL)$/ ) {
            $dir = $1;
        }
    }

    if ( my $pgtype = param('gtype') ) {
        if ( $pgtype eq 'graph' ) {
            $gtype = 'graph';
            $arrow = '--';
        }
        elsif ( $pgtype eq 'digraph' ) {
            $gtype = 'digraph';
            $arrow = '->';
        }
    }

    my $dot = <<EODOT;
$gtype $graphname {
    graph [ratio=fill overlap=false splines=true rankdir=$dir];
    edge [arrowhead=crow dir=forward samearrowhead=1];
    node [shape=record];
EODOT

    my %ports;
    my %nodes;
    my $node_count = 1;
    foreach my $class ( DBIx::Snug->list_all_classes() ) {
        my @cols = $class->all_columns;

        # create a port mapping to use later with from_port, to_port
        for ( my $i=0; $i<@cols; $i++ ) {
            $ports{$class}->{$cols[$i]} = $i+1;
        }

        # drawing edges to ports looks terrible with the current version of
        # graphviz so disable it by default and let it be enabled with with_ports=1
        my $colslbl = join( '\l|', @cols );
        my $nformat = '    node%d [label="%s|%s\l" shape="record"];';

        if ( param('with_ports') ) {
           $nformat = '    node%d [label="<f0>%s|%s\l" shape="record"];';
           $colslbl = join( '\l|', map { sprintf('<f%d> %s', $_+1, $cols[$_]) } 0..$#cols );
        }

        # TB/BT seems to need curly braces to get the records drawn right, while
        # LR/RL must not have them
        if ( $dir =~ /(?:TB|BT)/ ) {
            $nformat = '    node%d [label="{%s|%s\l}" shape="record"];';
            if ( param('with_ports') ) {
                $nformat = '    node%d [label="{<f0>%s|%s\l}" shape="record"];';
            }
        }

        $dot .= sprintf $nformat, $node_count, $class->table, $colslbl;
        $dot .= "\n";

        $nodes{$class} = $node_count;

        $node_count++;
    }

    my %weights = map { $_ => 0 } DBIx::Snug->list_all_classes();
    foreach my $class ( keys %weights ) {
        foreach my $column ( $class->all_columns ) {
            if ( $class->has_foreign_key($column) ) {
                $weights{$class}++;
            }
        }
    }

    foreach my $class ( DBIx::Snug->list_all_classes() ) {
        foreach my $column ( $class->all_columns ) {
            if ( $class->has_foreign_key($column) ) {
                my($fk_table,$fk_column,$fk_class) = $class->foreign_key( $column );

                $dot .= sprintf "    node%d:f%d %s node%d:f%d;\n", # [weight=%d];\n",
                #$dot .= sprintf "    node%d:port%d:_ %s node%d:port%d:_;\n", # [weight=%d];\n",
                    $nodes{$class},
                    $ports{$class}{$column},
                    $arrow,
                    $nodes{$fk_class},
                    $ports{$fk_class}{$fk_column},
                    $weights{$class};
            }
        }
    }

    $dot .= <<EODOT;
    label="Module relationships for loaded DBIx::Snug subclasses.";
}
EODOT

    open( my $fh, "> /tmp/$graphname.dot" );
    print $fh $dot;
    close $fh;

    return $dot;
}

=item png

Returns raw PNG data of the graph.

 print "Content-type: image/png\n\n";
 binmode(STDOUT);
 print $g->png;

=cut

sub png {
    my $self = shift;
    my $dot = $self->dot;
    my $binary = '/usr/bin/dot';

    if ( my $be = param('backend') ) {
        if ( $be eq 'dot' ) {
            $binary = '/usr/bin/dot';
        }
        elsif ( $be eq 'neato' ) {
            $binary = '/usr/bin/neato';
        }
        elsif ( $be eq 'twopi' ) {
            $binary = '/usr/bin/twopi';
        }
        elsif ( $be eq 'fdp' ) {
            $binary = '/usr/bin/fdp';
        }
        elsif ( $be eq 'circo' ) {
            $binary = '/usr/bin/circo';
        }
    }

    my( $dotfh, $tempfile) = tempfile();
    print $dotfh $dot;

    my $fh;
    eval {
        open( $fh, "$binary -Tpng $tempfile |" )
            or croak "Could not run /usr/bin/dot: $!";
    };

    binmode($fh);

    local $/ = undef;
    my $png = <$fh>;
    unlink $tempfile;

    return $png;
}
1;

# vim: et ts=4 sw=4 ai smarttab

__END__

=back

=head1 NOTES

This does not use GraphViz.pm from CPAN.    Using that module with ports and other graphviz
options that it does not know about requires a lot of hacking that just isn't worth it.

So far, the best combination is:

 graphviz.pl?backend=dot&rankdir=LR&gtype=digraph&with_ports=1

=head1 AUTHORS

 Al Tobey <tobert@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2006-2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

=cut

