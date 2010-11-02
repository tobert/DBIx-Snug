package DBIx::Snug::Join;

###########################################################################
#                                                                         #
# DBIx::Snug::DDL                                                         #
# Copyright 2006-2010, Albert P. Tobey <tobert@gmail.com>                 #
#                                                                         #
###########################################################################

use strict;
use warnings;
use Scalar::Util qw(blessed);
use Carp qw(cluck carp croak confess);
use Data::Dumper;

# package globals
# the counter can go up basically forever and is useful for combining
# multiple join objects using subqueries (prevents name collisions)
my $_table_alias_counter = 1;

# used to create SQL for passed-in restrictions
my %restrictions = (
    cond_equals    => { first => '=',      'last' => ''  },
    cond_like      => { first => 'LIKE %', 'last' => '%' },
    cond_in        => { first => 'IN ( ',  'last' => ')' },
    cond_notequals => { first => '=',      'last' => ''  }
);

=head1 NAME

DBIx::Snug::Join

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item new()

=cut

sub new {
    my( $type, %args ) = @_;

    confess "Must specify the class being joined in the 'from_class' argument."
        unless ( $args{from_class} );
    confess "'from_class' must be a subclass of DBIx::Snug"
        unless ( $args{from_class}->isa('DBIx::Snug') );

    $args{class} = delete $args{from_class};

    unless ( $args{table_alias} ) {
        $args{table_alias} = sprintf 'f%d_%s',
            $_table_alias_counter++,
            $args{class}->table;
    }

    # default to the non-PK columns of the referenced class without aliases
    if ( !exists $args{data_columns} ) {
        $args{data_columns} = { map { $_ => $_ } $args{class}->columns };
    }
    elsif ( ref($args{data_columns}) eq 'ARRAY' ) {
        $args{data_columns} = { map { $_ => $_ } @{$args{data_columns}} };
    }

    # initialize data members
    $args{_references} = [];

    my $self = bless \%args, $type;

    # allow one-shot join creation by passing references in an arrayref
    if ( $args{references} && ref $args{references} eq 'ARRAY' ) {
        foreach my $ref ( @{$args{references}} ) {
            $self->reference( %$ref );
        }
    }
    delete $self->{references};

    return $self;
}

=item reference()

=cut

sub reference {
    my $self = shift;
    my %ref = @_;

    confess "You must specify a 'to' class." unless ( $ref{to_class} );
    confess "The 'to' argument must be a DBIx::Snug subclass!"
        unless ( $ref{to_class}->isa('DBIx::Snug') );

    $ref{class} = delete $ref{to_class};

    # default to the non-PK columns of the referenced class without aliases
    if ( !exists $ref{data_columns} ) {
        $ref{data_columns} = { map { $_ => $_ } $ref{class}->columns };
    }
    elsif ( ref($ref{data_columns}) eq 'ARRAY' ) {
        $ref{data_columns} = { map { $_ => $_ } @{$ref{data_columns}} };
    }

    # default for table_alias
    unless ( $ref{table_alias} ) {
        $ref{table_alias} = sprintf 't%d_%s',
            $_table_alias_counter++,
            $ref{class}->table;
    }

    # check to see if the join type is valid then upper case it
    if ( exists $ref{join_type} ) {
        if ( $ref{join_type} !~ /^(?:NATURAL|LEFT|INNER|RIGHT|LEFT OUTER)$/ ) {
            confess "Invalid join type '$ref{join_type}'.";
        }
        else {
            $ref{join_type} = uc $ref{join_type};
        }
    }
    # default to plain JOIN when not specified
    else {
        $ref{join_type} ||= '';
    }

    # keep a reference to the parent object 
    $ref{_super} = $self;

    # bless the reference as the same class as the parent object
    # to allow joining to joins
    my $sub = bless \%ref, 'DBIx::Snug::Join';

    # add the reference to the top-level object
    push @{$self->_top->{_references}}, \%ref; # store the data, not the object

    return $sub;
}

# walk down to the top-level object
sub _top {
    my $self = shift;
    my $top = $self;
    while ( exists $top->{_super} ) {
        $top = $top->{_super};
    }
    return $top;
}

=item query()

=cut

sub query {
    my $self = shift;

    my( %select, @join, %where );

    foreach my $ref ( @{$self->{_references}} ) {
        _select( $ref, \%select );

        if ( ref $ref eq 'DBIx::Snug::Join' ) {
            push @join, $ref->{_super}->join_sql( $ref );
        }
        else {
            push @join, $self->join_sql( $ref );
        }
    }
    _select( $self, \%select );

    my $sql = sprintf "\tSELECT %s$/\tFROM %s$/\t%s",
        join( ",$/\t\t", map { "$_ AS $select{$_}" } sort keys %select ),
        join( ",$/\t\t", $self->{class}->table .' '.$self->{table_alias} ),
        join( "$/\t", @join );
    return $sql;
}

sub _select {
    my( $data, $select, $do_pk ) = @_;

    if ( $do_pk ) {
        foreach my $pk ( $data->{class}->primary_key ) {
            my $key = $data->{table_alias}.'.'.$pk;
            $select->{$key} = $pk
                unless ( grep { $_ eq $key } keys %$select
                      or grep { $_ eq $pk  } values %$select );
                
        }
    }
    foreach my $dcol ( keys %{$data->{data_columns}} ) {
        my $alias = $data->{data_columns}{$dcol};
        my $key = $data->{table_alias}.'.'.$dcol;
        $select->{$key} = $alias
            unless ( grep { $_ eq $alias } values %$select );
    }
}

=item join_sql()

=cut

sub join_sql {
    my( $self, $ref ) = @_;

    my $jsql = sprintf '%s JOIN %s %s',
                    $ref->{join_type},
                    $ref->{class}->table,
                    $ref->{table_alias};
            
    if ( $ref->{join_type} ne 'NATURAL' ) {
        my @ands;
        my $from = $self->{table_alias};
        my $to   = $ref->{table_alias};
        foreach my $key ( keys %$ref ) {
            next unless exists $restrictions{$key};

            foreach my $fcol ( keys %{$ref->{$key}} ) {
                my $tcol = $ref->{$key}{$fcol};
                my $fcol_table = $ref->{table_alias};
                my $tcol_table = $self->{table_alias};

                if ( $fcol =~ /(\w+)\.(\w+)/ ) {
                    $fcol = $2;
                    $fcol_table = $1;
                }

                if ( $tcol =~ /(\w+)\.(\w+)/ ) {
                    $tcol = $2;
                    $tcol_table = $1;
                }

                push @ands, sprintf '%s.%s%s%s.%s%s',
                    $fcol_table,
                    $fcol,
                    $restrictions{$key}->{'first'},
                    $tcol_table,
                    $tcol,
                    $restrictions{$key}->{'last'};
            }
        }
        $jsql .= " ON ($/\t\t" . join( "\t\tAND ", @ands ) . "$/\t )";
    }
    return $jsql;
}

sub all_columns {
    my $self = shift;
    return(
        $self->primary_key,
        $self->columns
    );
}

=item columns()

=cut

sub columns {
    my $self = shift;

    unless ( $self->{_columns} ) {
        my @cols;
        foreach my $ref ( $self, @{$self->{_references}} ) {
            foreach my $col ( keys %{$ref->{data_columns}} ) {
                # get the alias, not the real column name
                push @cols, $ref->{data_columns}{$col};
            }
        }
        $self->{_columns} = \@cols;
    }
    return @{ $self->{_columns} };
}

sub primary_key {
    my $self = shift;

    # only run the code to generate the primary key once per-object
    # (this could even be per-class if it's ever a performance problem)
    unless ( ref $self->{primary_key} eq 'ARRAY' ) {
        my %tmp_pk;

        # genereate the primary key based on what keys the join uses 
        foreach my $ref ( @{$self->{_references}} ) {
            my $super = ref($ref->{_super}) ? $ref->{_super} : $self;

            # for NATURAL joins, the join keys are those with the same names
            # on both sides of the join, regardless of other attributes
            if ( exists $ref->{join_type} && $ref->{join_type} eq 'NATURAL' ) {
                foreach my $ref_key ( $ref->{class}->all_columns ) {
                    foreach my $key ( $super->{class}->all_columns ) {
                        if ( $ref_key eq $key ) {
                            $tmp_pk{$key} = $ref;
                            #warn "NATURAL $key";
                        }
                    }
                }
            }
            # all other joins require specifying restrictions for the ON()
            # clause, so pull those out and put them in the JOIN's PK
            else {
                foreach my $key ( keys %$ref ) {
                    if ( exists $restrictions{$key} ) {
                        foreach my $col ( keys %{$ref->{$key}} ) {
                            my $pkcol = $ref->{$key}{$col};
                            $pkcol =~ s/^\w+\.//;
                            $tmp_pk{$pkcol} = $ref;
                            #warn "NOT NATURAL $pkcol";
                        }
                    }
                }
            }
        }

        $self->{primary_key} = [ sort keys %tmp_pk ];

        # keep this for easy lookups of what reference a column came from
        $self->{primary_key_src} = \%tmp_pk;
    }

    return @{$self->{primary_key}};
} 

sub table_alias {
    my $self = shift;
    return $self->{table_alias};
}

sub to_class {
    my $self = shift;
    return $self->{class};
}

sub _references {
    my $self = shift;
    return @{$self->{_references}};
}

# special function for use by DBIx::Snug::View, which subclasses
# DBIx::Snug, which is where the need for the %cols data structure
# comes from
sub _class_data_columns {
    my $self = shift;
    my %cols;

    # go through all of the data columns in all of the joined tables
    foreach my $ref ( $self, @{$self->{_references}} ) {
        foreach my $col ( keys %{$ref->{data_columns}} ) {
            my $alias = $ref->{data_columns}{$col};
            $cols{$alias} = [ $ref->{class}->column_pseudotype($col), undef ];
        }
    }
    # now, get the primary key columns, since they aren't all be in the
    # data_columns lists
    # does this need to unalias columns?
    foreach my $col ( $self->primary_key ) {
        my $ref = $self->{primary_key_src}{$col};

        # check the reference's parent object if there is one, since it
        # is where we really want to look for the column most of the time
        if ( $ref->{_super} && $ref->{_super}{class}->can($col) ) {
            $ref = $ref->{_super};
        }

        my $alias = $ref->{data_columns}{$col} || $col;
        $cols{$alias} = [ $ref->{class}->column_pseudotype($col), undef ];
    }

    return \%cols;
}

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

