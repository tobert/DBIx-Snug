package DBIx::Snug::REST;

###########################################################################
#                                                                         #
# DBIx::Snug::REST                                                        #
# Copyright 2008-2010, Albert P. Tobey <tobert@gmail.com>                 #
#                                                                         #
###########################################################################

=back

=head1 NAME

DBIx::Snug::REST

=head1 DESCRIPTION

A CGI::Application module that can be either subclassed or used directly
that exposes a lightweight REST interface to any of the loaded DBIx::Snug
subclasses.

The methods in this module are named and designed so that it can easily be
subclassed instead of CGI::Application for extension and customization.

=head1 SYNOPSIS

 #!/usr/bin/perl
 use strict;
 use warnings;
 use My::Snug::Module;
 use My::Snug::Module2;
 use My::Snug::Module3;
 use DBIx::Snug::REST;

 my $dbh = DBI->connect( ... );
 my $app = DBIx::Snug::REST->new($dbh);
 $app->run();

=head1 METHODS

=over 4

=cut

use strict;
use warnings;
use Carp qw(carp confess cluck);
use Data::Dumper; # I use this a lot when debugging

require DBIx::Snug;
require DBIx::Snug::Search;
require DBIx::Snug::Join;
require DBIx::Snug::View;

use base 'CGI::Application';
use JSON;

=item new()

Create a new CGI::Application based object.  It sets its default run mode,
which is called 'default' and pointed at the dbix_snug_rest_dispatch() method.

A database handle argument is required.

 my $app = DBIx::Snug::REST->new( $dbh );

=cut

sub new {
    my $type = shift;
    my( $dbh ) = grep { $_->isa('DBI::db') } @_;

    confess "An argument containing a DBI handle is required!"
        unless ( $dbh );

    # create the object using CGI::Application's constructor as if
    # this new() method did not exist
    my $self = $type->SUPER::new();

    # add in a _dbh attribute
    $self->{_dbh} = $dbh;

    $self->start_mode('rest_dispatch');
    $self->run_modes(
       rest_dispatch => 'dbix_snug_rest_dispatch'
    );

    return $self;
}

=item dbix_snug_rest_dispatch() [internal]

This is where all the functionality is.   Eventually, it may be possible to set this up
as a mod_perl handler.   It expects to be called as a CGI::Application method.

Note: This method is too big and needs to be broken up.

 $app->dbix_snug_rest_dispatch();

=cut

sub dbix_snug_rest_dispatch {
    my $self     =  shift;
    my $query    =  $self->query;
    my $method   =  uc($query->request_method || '');
    my $pinfo    =  $query->path_info();
       $pinfo    =~ s#^/+##; # remove leading slashes
    my @path     =  split( /\/+/, $pinfo );
    my $json     =  JSON->new();
    my $data_out =  { error => "No data." };
    my $qpackage =  undef;

    # maybe text/x-json ?
    # http://www.ietf.org/rfc/rfc4627.txt
    # IANA says application/json
    $self->header_add( -type => 'application/json' );

    # default URL - a hash of DBIx::Snug subclasses that can be managed
    unless ( $query->param() or @path > 0 ) {
        # returns a hash of perl class name => path spec
        # _mkpath() is near the bottom of this file
        return $json->encode( {
            map { $_ => _mkpath($_) } DBIx::Snug->list_all_classes
        } );
    }

    # figure out the action based on path
    my $action = shift @path;
    unless ( $action && $action =~ /^(?:get|create|update|delete)$/ ) {
        unshift @path, $action; # not an action - put it back on the stack

        # now see if there's a parameter for action
        $action = $query->param('action');
        unless ( $action && $action =~ /^(?:get|create|update|delete)$/ ) {
            carp "Unknown or unset action.   Defaulting to get.  Fix your app.";
            $action = 'get';
        }
    }

    # allow the package to be a parameter or in path_info:
    # foo.pl?package=My::DB::Node&action=get
    # foo.pl/get/My/DB/Node/1
    if ( $query->param('package') ) {
        $qpackage = $query->param('package');
    }
    else {
        $qpackage = join( '::', @path );
    }

    # find out what object is being queried s/\//::/ until we run out of matches
    while ( $qpackage =~ /::/ ) {
        my( $pkg ) = grep( /^$qpackage$/i, DBIx::Snug->list_all_classes);
        if ( $pkg ) {
            $qpackage = $pkg;
            last;
        }
        else {
            # strip off the last name one by one until either we run
            # out or find a match
            $qpackage =~ s/::[^:]+$//;
        }

        if ( $qpackage !~ /::/ ) {
            cluck "Ran out of packages searching path info.";
            last;
        }
    }

    # now truncate @path so just query parameters are left
    my @pkg = split /::/, $qpackage;
    splice @path, 0, scalar @pkg;

    # parameterize path (turn it into a hash)
    # only accept primary keys on PATH_INFO - all other data should go into
    # POST or PUT bodies
    my %params;
    my @pks = $qpackage->primary_key;
    
    # simple 1-argument form - probably fairly common and handy
    if ( @path == 1 ) {
        # seriously, only single PK tables are supported by this
        confess "Only one argument in path but $qpackage reports having more than one primary key.  Cannot continue."
            if ( @pks > 1 );

        $params{ $pks[0] } = $path[0];
    }
    # for everything else, decode the path into %params
    # /key/value/key/value form
    elsif ( @path % 2 == 0 ) {
        # change the string 'undef' to actual undef
        # so foo/undef/bar/1 becomes { foo => undef, bar => 1 } rather than
        # { foo => 'undef', bar => 1 }
        map { $_ = undef if ($_ eq 'undef') } @path;
        # ditto, true/false (TODO: is this desirable?)
        map { $_ = undef if ($_ eq 'false') } @path;
        map { $_ = 1     if ($_ eq 'true' ) } @path;

        # now assign values to %params using a loop rather than array->hash
        # assignment since it allows for normalization and better checking
        for ( my $i=0; $i<@path; $i+=2 ) {
            foreach my $pk ( @pks ) {
                # case-insensitive match
                if ( lc($path[$i]) eq lc($pk) ) {
                    # but preserve case in %params so later code doens't have
                    # to mess with it
                    $params{$pk} = $path[$i+1];
                    last;
                }
            }
        }
    }

    # now process normal query parameters, but only for PUT or POST
    # GET/DELETE don't need and explictly don't support more than PK parameters
    if ( $method ne 'GET' and $action ne 'get' and $method ne 'DELETE' ) {
        foreach my $p ( $query->param ) {
            if ( exists $params{$p} ) {
                carp "Already got parameter '$p' from PATH_INFO.  Skipping query parameter.";
                next;
            }

            $params{$p} = $query->param($p);
        }
    }

    # Dispatch according to REST/CRUD
    # read - %params wil only have primary key values or nothing
    if ( $method eq 'GET' or $action eq 'get' ) {
        $data_out = $self->dbix_snug_rest_get( $qpackage, \%params );
    }
    # create/update/delete
    elsif ( $method eq 'POST' ) {
        if ( $action eq 'create' ) {
            $data_out = $self->dbix_snug_rest_create( $qpackage, \%params );
        }
        elsif ( $action eq 'update' ) {
            $data_out = $self->dbix_snug_rest_update( $qpackage, \%params );
        }
        elsif ( $action eq 'delete' ) {
            $data_out = $self->dbix_snug_rest_delete( $qpackage, \%params );
        }
    }
    # create/overwrite
    elsif ( $method eq 'PUT' ) {
        if ( $action eq 'create' ) {
            $data_out = $self->dbix_snug_rest_create( $qpackage, \%params );
        }
        elsif ( $action eq 'update' ) {
            $data_out = $self->dbix_snug_rest_update( $qpackage, \%params );
        }
    }
    # delete
    elsif ( $method eq 'DELETE' ) {
        $data_out = $self->dbix_snug_rest_delete( $qpackage, \%params );
    }

    my $count = 0;
    if ( ref $data_out eq 'ARRAY' ) {
        $count = scalar @$data_out;
    }
    elsif ( ref $data_out eq 'HASH' ) {
        $count = 1;
    }

    # return in an extjs-friendly style
    return $json->encode({
        results => $count,
        data => $data_out
    });
}

=item dbix_snug_rest_get() [internal]

=cut

sub dbix_snug_rest_get {
    my( $self, $package, $p ) = @_;

    # no parameters means return a full listing
    if ( keys %$p == 0 ) {
        return [
            map { $_->as_hashref }
            $package->list_all( $self->{_dbh} )
        ];
    }
    # with a pk, return just the one object
    else {
        my $obj = $package->new( %$p, dbh => $self->{_dbh} );
        return $obj->as_hashref();
    }
}

=item dbix_snug_rest_create() [internal]

=cut

sub dbix_snug_rest_create {
    my( $self, $package, $p ) = @_;

    my $o = $package->create( %$p, dbh => $self->{_dbh} );
    return $o->as_hashref;
}

=item dbix_snug_rest_update() [internal]


=cut

sub dbix_snug_rest_update {

confess "Not implemented yet.";

}

=item dbix_snug_rest_delete() [internal]

=cut

sub dbix_snug_rest_delete {

confess "Not implemented yet.";

}

sub _mkpath {
    my $classname = shift;
    $classname =~ s#::#/#g;
    return lc($classname);
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

