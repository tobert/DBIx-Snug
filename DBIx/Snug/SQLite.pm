package DBIx::Snug::SQLite;

###########################################################################
#                                                                         #
# DBIx::Snug::SQLite                                                      #
# Copyright 2006-2010, Albert P. Tobey <tobert@gmail.com>                 #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
###########################################################################

use strict;
use warnings;
use base 'DBIx::Snug::DDL';
use Data::Dumper; # I use this a lot when debugging
use DBI;

=head1 NAME

DBIx::Snug::SQLite

=head1 SYNOPSIS

 use DBIx::Snug::SQLite;

=head1 DESCRIPTION

Implements support for SQLite databases.   Everything is taken care of at import.

=cut

our %typemap  = (
    int       => 'INTEGER',
    text      => 'TEXT',
    varchar   => 'TEXT',
    dttm      => 'INTEGER',
    timestamp => 'INTEGER',
    bool      => 'INTEGER'
);

# limitation: only single-key primary keys can have AUTOINCREMENT (I think)
sub table_ddl {
    my( $self, $table ) = @_;

    my $class = $self->find_table_class( $table );
    my $struct = $self->_get_class_struct( $class );

    my @pk_cols = $class->primary_key;
    my @columns;

    foreach my $pk ( @pk_cols ) {
        my $type = _get_type( $class, $pk );
        my $seq  = $class->sequenced_column;

        if ( $seq && $pk eq $seq ) {
            $type .= " PRIMARY KEY AUTOINCREMENT";
        }
        elsif ( @pk_cols == 1 ) {
            $type .= " PRIMARY KEY";
        }
        else {
            $type .= $self->default_ddl_frag( $class, $pk );
        }
        push @columns, "    $pk $type";
    }

    foreach my $col ( $class->columns ) {
        my $type = _get_type( $class, $col );
        $type .= $self->default_ddl_frag( $class, $col );
        push @columns, "    $col $type";
    }

    # multi-column primary keys get weakened in SQLite when one
    # of the keys is a sequence, which should work out OK since
    # the sequence should make things "unique enough"
    if ( @pk_cols > 1 && !$class->sequenced_column ) {
        push @columns, "    PRIMARY KEY(" . join(',',@pk_cols) . ")";
    }

    my $ddl = "CREATE TABLE $table ($/";
    $ddl .= join( ",$/", @columns );
    $ddl .= "$/)";
    return $ddl;
}

sub _get_type {
    my( $class, $col ) = @_;
    my $pseudotype = $class->column_pseudotype( $col );
    $pseudotype =~ s/\(.*$//;
    return $typemap{ $pseudotype };
}

1;

# vim: et ts=4 sw=4 ai smarttab

__END__

=head1 AUTHORS

 Al Tobey <tobert@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2006-2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

=cut

