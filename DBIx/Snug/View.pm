package DBIx::Snug::View;

###########################################################################
#                                                                         #
# DBIx::Snug::View                                                        #
# Copyright 2006-2010, Albert P. Tobey <tobert@gmail.com>                 #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
###########################################################################

use strict 'vars';
use warnings;
use Scalar::Util qw(blessed);
use Carp;
use Data::Dumper;
@DBIx::Snug::View::ISA = qw( DBIx::Snug );
our $AUTOLOAD;

=head1 NAME

DBIx::Snug::View - extra functionality for views

=head1 DESCRIPTION

This module lets you create views similarly to how tables are created in
DBIx::Snug, but with a little less specific knowledge of how the
source tables are put together, to keep maintenance easy.   Basically, a
view is expressed in terms of multiple DBIx::Snug::Join objects.

The most common use of views within applications I've built with DBIx::Snug
is making searching with DBIx::Snug::Search much simpler by having the 
view join in all of the lookup tables.   Care must be taken to make sure data
is filtered to the right level ;)

=head1 SYNOPSIS

=head1 METHODS

=over 4

=cut

sub setup {
    my $class = blessed($_[0]) ? blessed(shift) : shift;
    # mash all of the arguments into a hashref that will eventually
    # get blessed into the class's data data structure
    my $cdata = { @_ };

    # These members make code in DBIx::Snug work
    $cdata->{table} = $cdata->{view};
    $cdata->{primary_key} = [ $cdata->{'join'}->primary_key ];
    $cdata->{columns} = $cdata->{'join'}->_class_data_columns;

    # let the parent class do the rest of the work creating methods & stuff
    $class->SUPER::setup( %$cdata );
}

sub join {
    my $class = blessed($_[0]) ? blessed(shift) : shift;
    return $class->get_class_definition->{'join'};
}

sub view {
    my $class = blessed($_[0]) ? blessed(shift) : shift;
    return $class->get_class_definition->{view};
}

sub AUTOLOAD {
    my $self = shift;
    my($method) = ( $AUTOLOAD =~ m/([^:]+)$/ );

    return if ( $method eq 'DESTROY' );

    foreach my $ref ( $self->join->_top->_references ) {
        if ( $ref->table_alias eq $method ) {
            my $class = $ref->to_class;
            my %args;

            # unroll column aliases
            foreach my $key ( keys %$ref ) {
                if ( $key =~ /^cond_/ ) {
                    if ( ref $ref->{$key} eq 'HASH' ) {
                        foreach my $field ( keys %{$ref->{$key}} ) {
                            next unless $class->has_primary_key( $field );
                            my $local_name = $ref->{$key}{$field};
                            $args{$field} = $self->$local_name;
                        }
                    }
                    # arrayrefs are only for when the column names
                    # match between source and desintation tables,
                    # so there's nothing to do here
                }
            }

            # make sure the whole primary key is present
            foreach my $pk ( $class->primary_key ) {
                next unless ( $self->can($pk) );
                $args{$pk} = $self->$pk;
            }

            # copy the database handle
            if ( $self->can('dbh') ) {
                $args{dbh} = $self->dbh;
            }

            return $class->new( %args );
        }
    }

    confess "INVALID METHOD CALL TO $AUTOLOAD";
}

sub _autoload_object {
    my $class = blessed($_[0]) ? blessed(shift) : shift;
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

