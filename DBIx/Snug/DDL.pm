package DBIx::Snug::DDL;

###########################################################################
#                                                                         #
# DBIx::Snug::DDL                                                         #
# Copyright 2006-2010, Albert P. Tobey <tobert@gmail.com>                 #
#                                                                         #
###########################################################################

=back

=head1 NAME

DBIx::Snug::DDL

=head1 DESCRIPTION

DDL-specific code.   This is also the base class for database-specific
modules like DBIx::Snug::SQLite and DBIx::Snug::mysql.

Subclasses must be name EXACTLY the same as their DBI driver or
things will break.  The tradeoff is that no extra configuration is necessary
once you've loaded your chosen driver.

 DBD::mysql  => DBIx::Snug::mysql
 DBD::SQLite => DBIx::Snug::SQLite
 # to be written ...
 DBD::Oracle => DBIx::Snug::Oracle
 DBD::Sybase => DBIx::Snug::Sybase
 DBD::ODBC   => DBIx::Snug::ODBC

=head1 SYNOPSIS

=head1 METHODS

=over 4

=cut

use strict;
use warnings;
use Carp;
use File::Find;
use Data::Dumper; # I use this a lot when debugging

our $classes = DBIx::Snug->_classes_ref;

=item all_tables_ddl()

Runs table_ddl() for all DBIx::Snug classes currently loaded.
 
 use MyOrg::DB::OnCall;
 use MyOrg::DB::Domain;
 use MyOrg::DB::Node;
 my @ddl = DBIx::Snug::DDL->all_tables_ddl;

=cut

sub all_tables_ddl {
    my $self = ref($_[0]) ? ref(shift) : shift;
    my @ddls;

    # sort to make sure classes with references come after the classes they reference
    my @clist = sort {
        if ( grep( {$_ eq $b} $a->foreign_key_classes ) ) {
            #print "$a < $b because $a references $b\n";
            1;
        }
        elsif ( grep( {$_ eq $a} $b->foreign_key_classes ) ) {
            #print "$a > $b because $b references $a\n";
            -1;
        }
        # otherwise just sort by name
        else {
            $a cmp $b;
        }
    }
    # sort by the number of references to other clasess, descending
    # - must be desc or the second sort (which is above this) won't work
    sort {
        scalar($b->foreign_key_classes) <=> scalar($a->foreign_key_classes)
    }
    DBIx::Snug->list_all_classes;

    # now dump the DDL - everything should come out in the right order
    foreach my $class ( @clist ) {
        my $table = $classes->{$class}{table};
        my $ddl = $self->table_ddl( $table ) . ";$/$/";
        push @ddls, $ddl;
    }

    return wantarray ? @ddls : join( '', @ddls );
}

=item find_table_class()

Takes a table name and returns the class that wraps that table.

 my $table = DBIx::Snug::DDL->find_table_class( "job" );

=cut

sub find_table_class {
    my( $self, $class_table ) = @_;

    # all DDL in this system is delt with in lowercase
    $class_table = lc($class_table);

    # simply loop over all the classes
    foreach my $class ( keys %$classes ) {
        my $curr_table = lc($classes->{$class}{table});
        return $class if ( $curr_table eq $class_table );
    }
}

sub _get_class_struct {
    confess "Must provide a class name as an argument to get_class_struct()."
        unless ( @_ == 2 );

    my $self = shift;
    my $class = ref($_[0]) ? ref($_[0]) : $_[0];
    return $classes->{$class};
}

sub create_view_ddl {
    my( $self, $class ) = @_;
    return 'CREATE VIEW '.$class->view.' AS'.$/.$class->join->query;
}

# this might not work out in the long-run for portability ...
# for instance, what happens when you do this for Oracle?
#   foo_id NOT NULL DEFAULT foo_id_seq.NextVal
# I guess it'll (oracle) have to provide its own version of this method.
sub default_ddl_frag {
    my( $self, $class, $col ) = @_;
    my $val = $class->default( $col );

    my $ret = ' NOT NULL';

    # no default set in the class struct, so it's just 'NOT NULL'
    return $ret unless defined $val;

    if ( $val eq 'NULL' ) {
        $ret = ' DEFAULT NULL';
    }
    elsif ( $val =~ /^(?:true|false)$/ ) {
        $ret .= " DEFAULT ". $self->$val();
    }
    elsif ( $val =~ /\D/ ) {
        $ret .= " DEFAULT '$val'";
    }
    else {
        $ret .= " DEFAULT $val";
    }

    return $ret;
}

# overridable
# TODO: document why this module has its own boolean construct
sub false { 0 }
sub true { 1 }

1;

# vim: et ts=4 sw=4 ai smarttab

__END__

=back

=head1 AUTHORS

 Al Tobey <tobert@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2006-2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

=cut

