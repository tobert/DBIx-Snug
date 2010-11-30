package DBIx::Snug;

###########################################################################
#                                                                         #
# DBIx::Snug                                                              #
# Copyright 2006-2010, Albert P. Tobey <tobert@gmail.com>                 #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
# This is open source software.  Please see the LICENSE section at the    #
# end of this file or the README at the Github URL above.                 #
#                                                                         #
###########################################################################

# ONLY MODULES SHIPPED WITH PERL!
use strict 'vars';
use warnings;
use Carp;
# Scalar::Util has been standard since perl 5.8.0
use Scalar::Util qw(blessed looks_like_number);
use Data::Dumper; # I use this a lot when debugging

require DBIx::Snug::Join;
require DBIx::Snug::View;
require DBIx::Snug::DDL;
require DBIx::Snug::MySQL;
require DBIx::Snug::SQLite;
require DBIx::Snug::Search;

#   If you're reading this, then you've decided to take a look at the source
# code for DBIx::Snug.    One of the first things a savvy perl programmer
# will notice is the very short list of modules in use, and specifically
# very few modules from CPAN.   This is entirely intentional, and is the
# reason this module exists.
#   If you're looking for something that does not implement its own AUTOLOAD
# and symbol table hackery or uses x::y::z nifty module, this is not the place
# to look, since the goal of DBIx::Snug is to be tiny and easy to embed with
# some code and ship.    This is nearly impossible with DBIx::Class or
# Class::DBI.
#
#   The core OO hack in this module is avoiding AUTOLOAD and directly generating
# all of a subclass's getters & setters at compile time, when ->setup() is
# called.   It is very fast and, on mondern machines, has a negligable impact
# on compilation performance.  Check out setup() and init().
#
#   Another thing an astute developer will notice is that there are few tests
# in the distribution.   This is also intentional.    Wherever possible,
# assertions are embedded into DBIx::Snug to avoid a heavy test suite and to
# basically always insure correctness, even in the face of layered hacks,
# weird perl distributions, and gunged-up systems.

=head1 NAME

DBIx::Snug - the wheel, reinvented

=head1 DESCRIPTION

This class is the base for most of the other database wrapper classes in
DBIx::Snug.   It takes care of auto-generating all of the column accessor and
setter methods when init() is called (which is called for you by setup()).
Additional methods may live in the child class's .pm file.

If you're wondering, "why yet another ORM?" then see WHY_ANOTHER_ORM

=head1 SYNOPSIS

 package My::SubClass;
 use base 'DBIx::Snug';

 __PACKAGE__->setup(
     table => 'sub_table',
     primary_key => ['sub_table_id'],
     columns => [
        sub_table_id => [ 'int', 'sequence' ]
        col1 => [ 'text', 'NULL' ],
        col2 => [ 'text', 'NULL' ]
     ]
 );

 sub local_method_1 {
     ...
 }

 1;

=head1 TYPES

The class definitions include some type data that can be used by the DDL writers
to auto-generate DDL for different RDBMS's.    This should turn out to be a very
small subset of types that can easily be translated to various RDBMS's.

All dates are represented as dttm, which is always stored as an unsigned integer.
It will use Unix epoch time, which is the number of seconds that have passed
since midnight January 1, 1970 UTC.

 ******************************************************
 * type       * SQLite  * MySQL      * Oracle         *
 ******************************************************
 * int        * INTEGER * INT(11)    * NUMBER         *
 * text       * TEXT    * TEXT       * VARCHAR2(4000) *
 * varchar(n) * TEXT    * VARCHAR(n) * VARCHAR2(n)    *
 * bool       * INTEGER * INT(1)     * INT(1)         *
 * dttm       * INTEGER * INTEGER    * NUMBER         *
 ******************************************************
 * note: the oracle types are a quick guess at the moment

=head1 METHODS

Methods marked as [CLASS METHOD] may be called on either the package or an object and
will behave the same either way.   Methods marked [OBJECT METHOD] must be called on
instantiated objects and will die if called on the package.

 $object->class_method();
 $object->object_method();

 MY::Package->class_method();

 my $class = "My::Package";
 $class->class_method();

=over 4

=cut

my %classes;
my $global_dbh;

# This provides a reference to %classes to be used by child modules to this one.   
sub _classes_ref { \%classes }

# creates the class from the datastructure passed in by the user
sub init {
    my $class = shift;

    return if ( $classes{$class}->{instantiated} );
    $classes{$class}->{instantiated} = 1;

    my $isa = $class . '::ISA';
    unless ( grep(/^DBIx::Snug$/, @{$isa}) ) {
        push @{$isa}, 'DBIx::Snug';
    }

    my @columns = $class->columns;
    my @pk = $class->primary_key;

    # ################################################################### #
    # The following section creates all of the getters/setters at startup #
    # time, avoiding usage of AUTOLOAD.                                   #
    # ################################################################### #
    # Instantiating the methods right away like this incurs a negligible
    # performance impact at startup (as compared to AUTOLOAD), a performance
    # boost during runtime, and makes UNIVERSAL::can() work.

    foreach my $col ( @columns ) {
        # get method, proxies to _get_column
        # - always query the database for non-primary-key columns rather than
        #   implementing some kind of complicated caching scenario
        # - _get_column will replace this reference with a new one that is
        #   pre-built and should perform better
        my $method = $class . '::' . $col;
        *{$method} = sub {
            shift->_get_column( $col, @_ );
        }
        unless $class->can( $col );

        # set method, proxies to _set_column
        my $setcol = 'set_'.$col;
        my $set_method = $class . '::' . $setcol;
        *{$set_method} = sub {
            shift->_set_column( $col, @_ );
        }
        unless $class->can( $setcol );
    }

    # primary keys are stored in the object so just return them
    foreach my $col ( @pk ) {
        my $method = $class . '::' . $col;
        *{$method} = sub { shift->{$col}; };
        # no setting of primary keys (unless the subclass implements it)!
    }

    # add an id() method for simple primary key classes
    if ( @pk == 1 ) {
        my $method = $class . '::id';
        *{$method} = sub { shift->{$pk[0]} };
    }
    
    # Many classes/tables have a name field.  When these are properly named,
    # they make it easy to find the field programatically, so provide a
    # shorthand method for accessing names to make polymorphism easier.
    my $class_name_field = $class->table . '_name';
    if ( $class->can($class_name_field) ) {
        my $method = $class . '::name';
        *{$method} = sub { shift->_get_column( $class_name_field, @_ ) };
    }
}

# This is the default proxy for most get methods.
# It creates a new subref and replaces the method in the object
# with the new, optimized subroutine on-the-fly then calls into it.
sub _get_column {
    my( $self, $column ) = @_;
    my $class = ref($self) ? ref($self) : $self;

    # handle methods that need to go back up to the super class
    if ( $class->super ne 'DBIx::Snug' ) {
        unless ( $classes{$class}->{columns}{$column} ) {
            $class = $class->super;
        }
    }

    my $table = $classes{$class}->{table};
    my $pk_query = $class->primary_key_query;
    my $query = "SELECT $column FROM $table WHERE $pk_query";

    my @pk_vals = $self->primary_key_values;

    # the first time get_column is called, it will replace the sub
    # with a "real" one so the query isn't built up on every call
    # remove this if there's any trouble ... this could very well
    # be a premature optimization .. then again, some methods are
    # called 10's of times in every loop of controller and would benefit
    my $method_name = $class . '::' . $column;
    my $method = sub {
        my $obj = shift;
        unless ( $obj->{_cache}{$method_name} ) {
            my $sth = $obj->dbh->prepare_cached( $query );
            $sth->execute( $obj->primary_key_values );
            my( $result ) = $sth->fetchrow_array;
            $sth->finish;
            if ( !defined($result) or length($result) < 1024 ) {
                $obj->{_cache}{$method_name} = $result;
            }
            else {
                return $result;
            }
        }
        return $obj->{_cache}{$method_name};
    };

    # turn off warnings in this block rather than leaving them off globally
    REPLACEMETHOD: {
        no warnings;
        *{$method_name} = $method; # replace the method in perl's symbol table
        use warnings;
    }

    $method->( $self );
}

sub _set_column {
    my( $self, $column, $value ) = @_;
    my $class = ref($self) ? ref($self) : $self;

    # always invalidate the whole cache
    $self->{_cache} = {};

    my $query = sprintf "UPDATE %s SET %s = ? WHERE %s",
        $classes{$class}->{table},
        $column,
        $class->primary_key_query;

    my $sth = $self->dbh->prepare( $query );
    my $result = $sth->execute( $value, $self->primary_key_values );
    $sth->finish;
    return $result;
}

=item new() [CLASS METHOD]

See the individual classes.    The only thing to note here is the "skip_check"
argument which causes the query to check the backing row to be skipped.

=cut

sub new {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my @pk = $class->primary_key;
    my %args = $class->process_named_arguments( @_ );
    my $self = bless {}, $class;

    die "Class \"$class\" is not supported by DBIx::Snug->new."
        unless exists $classes{$class};

    # move 'id' argument to the proper pk column name for simple pk's
    if ( $args{id} && @pk == 1 ) {
        $args{$pk[0]} = CORE::delete $args{id};
    }

    # decode any columns that need it
    foreach my $col ( $class->all_columns ) {
        next unless exists $args{$col};
        $args{$col} = $class->decode_column( $col, $args{$col} );
    }

    # get the arguments from %args
    foreach my $key ( 'dbh', @pk ) {
        $self->{$key} = $args{$key};
        confess "$class: Required parameter \"$key\" missing in call to new"
            unless ( $args{skip_check} || (exists $args{$key} && defined $args{$key}) );
    }

    confess "$class: Invalid object parameters or nonexistent object row."
        unless ( $args{skip_check} || $self->as_hashref );

    return $self;
}

=item create() [CLASS METHOD]

Ditto.

=cut

sub create {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $sequence = $class->sequenced_column;
    my %args = $class->process_named_arguments( @_ );
    my $dbh = $args{dbh}
        || confess "No valid dbh was argument passed to create().";
    my @insert_cols = (); 
    my @insert_args = ();

    # not allowed to pass in a value for the sequenced column
    if ( $sequence ) {
        foreach my $key ( keys %args ) {
            confess "$class: Cannot set sequenced columns in $class."
                if ( $key eq $sequence );
        }
    }

    # HACKISH: fix this up better soon
    # the parent class has to have a parent() method ... DBIx::Snug should
    # never have a parent() method or this will break
    if ( $class->super ne 'DBIx::Snug' && $class->super->can('child_class') ) {
        # this should sorta-kinda work as long as the column names
        # always match up and DBI->last_insert_id works as expected
        my $s = $class->super->create( %args, child_class => $class );
        foreach my $pk ( $s->primary_key ) {
            push @insert_cols, $pk;
            push @insert_args, $s->$pk;
        }
    }

    # verify all of the columns are present
    foreach my $col ( $class->all_columns ) {
        next if ( $sequence && $col eq $sequence ); # skip sequences on insert

        # allow not setting columns that have defaults set by the database
        my $col_default = $class->default($col);
        if ( defined $col_default && !exists $args{$col} ) {
            next;
        }
        # some are defined specifically as NOT NULL - throw an exception when
        # they're not set in %args
        elsif ( !defined $col_default && !exists $args{$col} ) {
            confess "$class: Missing argument \"$col\" in create().";
        }

        push @insert_cols, $col;
        push @insert_args, $class->decode_column( $col, $args{$col} );
    }

    # some table rows can be created with only an id
    if ( @insert_cols == 0 ) {
        @insert_cols = $class->primary_key;
        @insert_args = map { undef } @insert_cols;
    }

    my $query = sprintf "INSERT INTO %s (%s) VALUES (%s)",
        $classes{$class}->{table},
        join( ', ', @insert_cols ),
        join( ',', map { '?' } @insert_cols );

    $dbh->do( $query, undef, @insert_args );

    if ( $sequence ) {
        my $table = $classes{$class}->{table};
        # FIXME: possible portability problem with last_insert_id
        my $newid = $dbh->last_insert_id( undef, undef, $table, $sequence );
        $args{$sequence} = $newid;
    }

    $args{skip_check} = 1;

    return $class->new( %args, dbh => $dbh );
}

=item exists() [CLASS METHOD]

See if an item exists in the database.

 unless ( $class->exists( dbh => $dbh, foo_name => $x ) ) {
     ... # stuff
 }

=cut

sub exists {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my %args = $class->process_named_arguments( @_ );

    confess "exists() REQUIRES a database handle in the named argument 'dbh'!"
        unless ( $args{dbh} );

    my $query = sprintf "SELECT %s FROM %s WHERE ",
        join(',', $class->primary_key),
        $class->table;

    my( @where, @qargs );

    # if the entire primary key is available in the arguments, use only that
    my $all_pks_present = 1;
    foreach my $pk ( $class->primary_key ) {
        if ( exists $args{$pk} ) {
            push @where, "$pk = ?";
            push @qargs, CORE::delete $args{$pk};
        }
        else {
            $all_pks_present = undef;
        }
    }

    # If part(s) of the primary key is missing, search on all arguments
    # that match columns in the table (makes searching by name work).
    unless ( $all_pks_present ) {
        foreach my $key ( keys %args ) {
            if ( $class->has_column($key) ) {
                push @where, "$key = ?";
                push @qargs, $args{$key};
            }
        }
    }

    if ( @where == 0 ) {
        confess "Not enough arguments to use new_or_create()!";
    }

    $query .= join( ' AND ', @where );

    my $sth = $args{dbh}->prepare( $query );
    $sth->execute( @qargs );

    my $pk = $sth->fetchrow_hashref('NAME_lc');

    # rows() is not very portable
    #   DBD::mysql reports the number of rows the query returned
    #   DBD::Oracle reports how many have been fetched
    if ( $sth->rows > 0 && $sth->fetchrow_hashref ) {
        warn "Query: $query";
        warn "Args: " . join( ', ', @qargs );
        confess "Too many rows (".$sth->rows.")!  Refine the arguments to this method!";
    }

    # this should be reliable even in the face of different DBD implementations
    if ( $sth->rows == 0 || !defined $pk ) {
        return undef;
    }
    else {
        return 1;
    }
}

=item new_or_create() [CLASS METHOD]

Takes the same arguments as new(), but instead of crashing when the backend
row doesn't exist, it calls create() then returns the object.

 my $obj = My::Subclass->new_or_create(
    pk_id => $foo,
    data1 => $bar
 );

=cut

sub new_or_create {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my %args = $class->process_named_arguments( @_ );

    confess "new_or_create() REQUIRES a database handle in the named argument 'dbh'!"
        unless ( $args{dbh} );

    if ( $class->exists(%args) ) {
        my @objects = $class->search( %args );

        if ( @objects == 0 ) {
            $objects[0] = $class->new( %args );
        }
        elsif ( @objects == 1 ) {
            return $objects[0];
        }
        else {
            my $num = scalar @objects;
            confess "Too many ($num) objects match parameters to new_or_create()!";
        }
    }
    else {
        return $class->create( @_ );
    }
}

=item delete() [OBJECT, CLASS]

Delete the row from the database.

=cut

sub delete {
    my $self = shift;
    my $dbh = $self->require_dbh( @_ );

    unless ( ref($self) ) {
        $self = $self->new( @_ );
    }
    
    my $query = sprintf "DELETE FROM %s WHERE %s",
        $self->table,
        $self->primary_key_query;

    $dbh->do( $query, undef, $self->primary_key_values );
}

=item process_named_arguments() [INTERNAL, CLASS METHOD]

Takes a list of arguments, flattens objects into the arg hash, and returns
a hash with all the data in it.

=cut

# converts objects to id's for things like job => $job
# instead of job_id => $job->id
sub process_named_arguments {
    my $class = shift;
    my @args;

    if ( @_ % 2 == 0 ) {
        @args = @_;
    }
    elsif ( ref $_[0] eq 'ARRAY' ) {
        @args = @{ $_[0] };
    }
    elsif ( ref $_[0] eq 'HASH' ) {
        @args = %{ $_[0] };
    }
    else {
        confess "$class: Invalid argument to process_named_arguments()";
    }

    my %args_out;

    for ( my $idx=0; $idx<=$#args; $idx+=2 ) {
        my( $key, $ikey, $value ) = ( $args[$idx], $args[$idx], $args[$idx+1] );
        # ikey is $key with _id on the end but avoiding _id_id
        $ikey =~ s/(_id)?$/_id/;

        my $vtype = blessed($value);

        # when the value is an object, chances are it needs to be dereferenced
        if ( $vtype && $value->isa('DBIx::Snug') ) {
            # $key is a method on object, so call it
            if ( $value->can($key) ) {
                $args_out{$key} = $value->$key();
            }
            # caller is using shorthand syntactic sugar which lets you
            # drop _id from the key name when passing in an object
            elsif ( $value->can($ikey) ) {
                $args_out{$ikey} = $value->$ikey();
            }
            # lastly, sometimes the shorthand allows things like:
            # dependent_job => $job - obviously, $job doesn't have a
            # dependent_job_id method, so dig through the class metadata to
            # find the name of the column being referenced and call it as
            # a method - this should be pretty strict about only working
            # with foreign keys - anything else is a bug
            elsif ( exists $classes{$class}->{columns}{$ikey} ) {
                my $c = $classes{$class}->{columns}{$ikey};
                if ( defined $c->[2] && defined $c->[3] && $vtype eq $c->[2] ) {
                    my $method = $c->[3];
                    $args_out{$ikey} = $value->$method();
                }
            }
        }

        # copy everything
        if ( !exists $args_out{$key} ) {
            $args_out{$key} = $value;
        }
    }

    return %args_out;
}

=item set_global_dbh()

Set a global database handle for DBIx::Snug that all subobjects will use unless
a different handle is explicitly passed in.

This will be returned by require_dbh() when all other attempts to find a handle in
the arguments to a method have failed.

 DBIx::Snug->set_global_dbh( $dbh );

=cut

sub set_global_dbh {
    my( $class, $dbh ) = @_;
    $global_dbh = $dbh;
}

=item dbh()

Returns the database handle passed to new().

 my $dbh = $object->dbh;

 $object->dbh->do( ... );

=cut

sub dbh { shift->{dbh} }

=item require_dbh(@_) [CLASS METHOD]

This is just shorthand for subclasses to require a database handle argument in custom
subroutines so the same "unless $dbh confess" code doesn't get repeated all over.

 sub foo {
     my $self = shift;
     my $dbh = $self->require_dbh(@_);
 }

=cut

sub require_dbh {
    my $self = shift;
    my( $package, $filename, $line, $method, $hasargs ) = caller;

    if ( ref $self && UNIVERSAL::isa($self, __PACKAGE__) && $self->can('dbh') ) {
        return $self->dbh;
    }

    if ( @_ == 0 ) {
        confess "A 'dbh' argument is required by method '$method' but no arguments were passed to it.";
    }

    if ( @_ % 2 == 0 ) {
        my %args = @_;
        unless ( exists $args{dbh} ) {
            confess "A 'dbh' argument is required by method '$method'";
        }

        unless ( $args{dbh}->isa('DBI::db') ) {
            confess "The available 'dbh' parameter does not appear to be a DBI handle.";
        }

        return $args{dbh};
    }

    if ( my($dbh) = grep { $_->isa('DBI::db') } @_ ) {
        return $dbh;
    }

    if ( $global_dbh ) {
        return $global_dbh;
    }

    confess "A 'dbh' argument is required by method '$method'";
}

=item list_all() [CLASS METHOD]

Lists all objects in the table.   This can be slow for lots of objects.  You must pass
in a database handle since there's no other sane way to get one.

 my @objects = My::Class->list_all($dbh);

=cut

sub list_all {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $dbh = shift;

    my $query = sprintf "SELECT %s FROM %s",
        join( ', ', map { $_.' AS '.$_ } $class->primary_key ),
        $class->table;

    return $class->query_to_objects( $dbh, $query );
}

=item as_hashref() [OBJECT METHOD]

Returns all of the data elements of the object as a hashref.  This is 
much faster than fetching them one at a time.

 my $href = $obj->as_hashref;

 use Data::Dumper;
 warn Dumper($href); # display the backend data

=cut

sub as_hashref {
    my $self = shift;

    my @cols;
    foreach my $col ( $self->all_columns ) {
        push @cols, "$col AS $col";
    }

    unless ( $self->{href_query} ) {
        $self->{href_query} = join( ' ',
            'SELECT',
            join(', ', @cols ),
            'FROM',
            $self->table,
            'WHERE',
            $self->primary_key_query
        );
    }

    #warn $/ . $/ . $self->{href_query} . $/ . $/;
    my $sth = $self->dbh->prepare_cached( $self->{href_query} );
    $sth->execute( $self->primary_key_values );
    my $rv = $sth->fetchrow_hashref;
    $sth->finish;

    return $rv;
}

=item search()

This method sets up and creates a default search using DBIx::Snug::Search
(bundled with DBIx::Snug).

For most simple cases, it can be used unmodified:

 $object->search( foo_field_like => $value, dbh => $dbh );

To add more sophisticated search features without giving up the default stuff,
override search() in your subclass then call $self->search_object() which will
return the DBIx::Snug::Search object before running the query.

 package My::Package;
 sub search {
     my $self = shift;
     my $search = $self->search_object( @_ );

     # custom search here ...

     return $search->execute;
 }

To have it search one class's table but return another class, pass in the
return_class parameter.   For example, if you have table AB with fields
A_id and B_id and table B with just B_id and want to return all the B's that
have entries in table AB, do this:

 AB->search( dbh => $dbh, return_class => 'B' );

=cut

sub search {
    my $self  = shift;
    my $class = ref($self) ? ref($self) : $self;
    my $dbh   = $self->require_dbh(@_);
    my %args  = @_;

    my $return_class = CORE::delete $args{return_class} || $class;

    # unroll objects into search parameters automatically
    # even being lazy should work ok with this, e.g.:
    #  $class->search( foobar => $object1, barbaz => $object2 );
    # technically even the following will work
    #  $class->search( $obj1 => $obj2 )
    # where foobar and barbaz are completely arbitrary names just to
    # make the hash shape up correctly
    for ( my $i=0; $i<@_; $i++ ) {
        my $arg = $_[$i];

        if ( blessed($arg) && $arg->can('all_columns') ) {
            foreach my $col ( $arg->all_columns ) {
                if ( !exists $args{$col} && $class->has_column($col) ) {
                    $args{$col} = $arg->$col;
                }
            }
        }
        # Note: hacked this in after a 2-year hiatus .. this might
        # not be the right approach or place for this .. testing will tell
        # simple queries
        elsif ( $class->has_column($arg) ) {
            $args{$arg} = $_[++$i];
        }
    }

    my $search = $self->search_object( %args );

    # DBIx::Snug::Search returns an array of hashrefs - convert those to objects
    # and return that list instead.
    my @out;
    foreach my $obj_href ( $search->execute($dbh) ) {
        my $obj = $return_class->new( %$obj_href, dbh => $dbh );
        push @out, $return_class->new( %$obj_href, dbh => $dbh );
    }
    #if ( @out == 0 ) {
    #    warn "QUERY: ".$search->query;
    #    warn "ARGS: ".join(', ', @{$search->bindvals});
    #}

    return @out;
}

=item search_one()

Exactly like search() but returns a single object.    Exceptions are thrown for any number of results other than 1.

 my $res = My::Package->search_one( ... );

=cut

sub search_one {
    my @out = shift->search( @_ );
    if ( @out > 1 ) {
        confess "More than one result for search_one().  Broken search query.";
    }
    elsif ( @out == 0 ) {
        confess "No results for search_one().  Broken search query or bad data.";
    }
    return $out[0];
}

# This function builds a DBIx::Snug::Search object based on the parameters
# and returns that - most of the time it'll be driven by search() which
# will execute the search then convert the results to objects.
#
# The nearby table stuff is probably a bad idea and may be removed if
# I don't find any use for it.
sub search_object {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my %args = $class->process_named_arguments( @_ );
    CORE::delete $args{dbh};

    my $search;
    if ( $args{on} ) {
        $search = DBIx::Snug::Search->new( @{CORE::delete $args{on}} );
    }
    else {
        $search = DBIx::Snug::Search->new( $class->primary_key );
    }

    # easily handle passing through methods like order_by
    foreach my $arg ( keys %args ) {
        if ( $search->can($arg) ) {
            my $val = CORE::delete $args{$arg};
            if ( ref($val) eq 'ARRAY' ) {
                $search->$arg( @$val );
            }
            else {
                $search->$arg( $val );
            }
        }
    }

    my $query_count = 0;
    foreach my $arg ( keys %args ) {
        my( $s_method, $s_table, $s_column );

        # simple column searches
        if ( $class->has_column($arg) ) {
            $search->simple( $class->table, $arg, $args{$arg} );
            $query_count++;
            next;
        }
        elsif ( $arg =~ /(\w+)_(like|regex|rlike)/ ) {
            ( $s_column, $s_method ) = ( $1, $2 );
            if ( $class->has_column($s_column) ) {
                $search->$s_method( $class->table, $s_column, $args{$arg} );
                $query_count++;
                next;
            }
        }
        elsif ( $arg eq 'distinct' ) {
            my $distinct = CORE::delete $args{$arg};
            my @on;
            foreach my $on_field ( @{$search->on} ) {
                if ( $on_field eq $distinct ) {
                    unshift @on, "DISTINCT $on_field";
                }
                else {
                    push @on, $on_field;
                }
            }
            my $sub = sprintf "SELECT %s FROM %s", join(',', @on ), $class->table;
            $search->select( $sub );
            $query_count++;
            next;
        }
        # undocumented, unused ... maybe handy someday
        #elsif ( $arg =~ /(\w+)_in/ ) {
        #    my $subquery = $args{$arg}->query;
        #    $search->where( ' IN ('.$subquery.')' );
        #}
        else {
            $s_column = $arg;
        }

        # column was not found in $class's table - search FK tables
        my $fk_class;
        if ( !$s_table ) {
            if ( $fk_class = $class->_nearest($s_column) ) {
                $s_table = $fk_class->table;
                $s_method ||= 'simple';
            }
        }

        # add the argument to the search, but since it's being found in another
        # table it needs to be wrapped in a subquery
        if ( $s_table && $s_column && $s_method ) {
            my $sql = sprintf "SELECT %s FROM %s WHERE %s IN ( SELECT %s FROM %s WHERE ",
                join( ',', @{$search->on} ),
                $class->table,
                join( ',', $fk_class->primary_key ),
                join( ',', $fk_class->primary_key ),
                $fk_class->table;

            if ( defined $s_method && $s_method ne 'simple' ) {
                $sql .= $search->__like( uc $s_method, $s_table, $s_column, $args{$arg} );
            }
            else {
                $sql .= $search->__simple( $s_table, $s_column, $args{$arg} );
            }
            
            $sql .= ")";
            $search->select( $sql, $args{$arg} );
            $query_count++;
        }
        else {
            confess "Failed to construct a usable search with argument '$arg'.";
        }
    }

    # no restrictions defaults to SELECT * FROM table
    if ( $query_count == 0 ) {
        $search->select(
            'SELECT '.join(',',@{$search->on}).' FROM '.$class->table
        );
    }
    #warn $search->query;

    return $search;
}

sub _nearest {
    my( $self, $column ) = @_;
    my $class = ref($_[0]) ? ref(shift) : shift;

    foreach my $possible_col ( $class->all_columns ) {
        if ( $possible_col eq $column ) {
            return( $column, $self->table, $class );
        }

        # also check immediately adjacent tables via FK for possible joins
        else {
            # slow, brute force search
            my $found_in_class;
            foreach my $fkclass ( $class->foreign_key_classes ) {
                if ( $fkclass->has_column($column) ) {
                    croak "Multiple matches for column $column in multiple classes ($fkclass and $found_in_class).  Cowardly refusing to choose one."
                        if ( $found_in_class );
                    $found_in_class = $fkclass;
                }
            }
            if ( $found_in_class ) {
                return( $class, $found_in_class->table, $found_in_class );
            }
        }
    }
}

=item sth_to_objects() [CLASS METHOD]

Takes a database statement handle, loops over its results, then
returns a list of objects.   The return values MUST be named
properly, so use SELECT foo AS foobar to be safe.

Yes, this does pretty much the same thing as the same method
in Class::DBI.

 my $sth = $dbh->prepare( ... );
 $sth->execute( ... );
 return $self->sth_to_objects($sth);

=cut

sub sth_to_objects {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $sth = shift;

    my @rv;
    while ( my $href = $sth->fetchrow_hashref('NAME_lc') ) {
        $href->{dbh} = $sth->{Database};
        push @rv, $class->new( %$href );
    }
    return @rv;
}

=item where_to_objects() [CLASS METHOD]

An even shorter form of sth_to_objects.   Pass in the WHERE clause (not including "WHERE") and an arrayref with the arguments that need to go into $sth->execute and you're done.   It calls sth_to_objects().

 $class->where_to_objects(
     $dbh,
     "foo=? AND bar=? AND baz=?",
     [ $foo, $bar, $baz ]
 );

=cut

sub where_to_objects {
    my( $class, $dbh, $where, $args ) = @_;
    confess "Invalid number of arguments to where_to_objects()"
        unless ( @_ == 4 );

    my $query = sprintf "SELECT %s FROM %s WHERE %s",
        join( ', ', map { "$_ AS $_" } $class->primary_key ),
        $class->table,
        $where;

    my $sth = $dbh->prepare_cached( $query );
    $sth->execute( @$args );

    return $class->sth_to_objects( $sth );
}

=item query_to_objects()

Just like sth_to_objects/where_to_objects, but it expects a query as the first
argument and an arrayref of args as the second.

 my $query = "SELECT foo FROM bar WHERE baz=?";
 my $args  = [ $baz ];
 $class->query_to_objects( $dbh, $query, $args );

=cut

sub query_to_objects {
    my( $class, $dbh, $query, $args ) = @_;

    my $sth = $dbh->prepare_cached( $query );
    $sth->execute( @$args );

    return $class->sth_to_objects( $sth );
}

=item table() [CLASS METHOD]

Returns the table name the class references.

 my $tbl = $object->table;

=cut

sub table {
    my $class = ref($_[0]) ? ref(shift) : shift;
    $classes{$class}->{table};
}

=item columns() [CLASS METHOD]

Returns a list of columns handled by the table NOT including the primary key.

 my @cols = $class->columns;

=cut

sub columns {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my @cols;
    foreach my $col ( $class->all_columns ) {
        next if ( $class->has_primary_key($col) );
        push @cols, $col;
    }
    return @cols;
}

=item super() [INTERNAL, CLASS METHOD]

Returns the immediate ancestor of the object/class.   Most of the time this
will be DBIx::Snug.  If a key is defined as 'super' in the 2nd value of the column
structure, the 3rd value will be returned (which should always be a class name).

=cut

sub super {
    my $class = shift;
    foreach my $cc ( $class->all_columns ) {
        my $col = $classes{$class}->{columns}{$cc};
        if ( $col->[1] && $col->[1] eq 'super' ) {
            return $col->[2];
        }
    }
    return 'DBIx::Snug';
}

=item has_column() [CLASS METHOD]

Returns true if the class has the column.

 if ( $class->has_column('foo') ) {
    ...
 }

=cut

sub has_column {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $col = shift;

    if ( grep { $_ eq $col } $class->all_columns ) {
        return 1;
    }
    return undef;
}

=item has_primary_key() [CLASS METHOD]

Returns true if the passed-in column name is a primary key.  Returns false
for non-primary-key columns.    Throws an exception if the column does not
exist in the class's table.

 if ( $class->has_primary_key('col1') ) {
     ...
 }

=cut

sub has_primary_key {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $col = shift;

    confess "$class: '$col' is not a column in backing table."
        unless exists $classes{$class}->{columns}{$col};

    if ( grep { $_ eq $col } @{ $classes{$class}->{primary_key} } ) {
        return 1;
    }
    return undef;
}

=item primary_key() [CLASS METHOD]

Returns only the primary key columns.

 my @pk = $object->primary_key;

=cut

sub primary_key {
    my $class = ref($_[0]) ? ref(shift) : shift;
    return @{ $classes{$class}->{primary_key} };
}

=item sequence_column()

Returns the name of the column that is sequenced.   undef if there is
no sequence for the table.

=cut

sub sequenced_column {
    my $class = ref($_[0]) ? ref(shift) : shift;
    foreach my $col ( $class->primary_key ) {
        my $default = $class->default( $col );
        if ( $default ) {
            if ( $default eq 'sequence' ) {
                return $col;
            }
            elsif ( $default eq 'super' ) {
                return $class->super->sequenced_column;
            }
        }
    }
    return undef;
}

=item all_columns() [CLASS METHOD]

Returns a list of all table columns.

 my @all = $class->all_columns;

=cut

sub all_columns {
    my $class = ref($_[0]) ? ref(shift) : shift;
    keys %{ $classes{$class}->{columns} };
}

=item default() [CLASS METHOD]

Returns the default value for a column, as defined in the class structure.  To
see this in use, see DBIx::Snug::DDL.    Columns with a default set to undef
will have the string 'NULL' returned.

 my $default = $class->default( 'col1' );

=cut

sub default {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $column = shift;
    return $classes{$class}->{columns}{$column}->[1];
}

sub decode_column {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my( $col, $value ) = @_;

    my $type = $class->column_pseudotype( $col );
    
    # decodes date/time down to Unix epoch time
    if ( $type eq 'dttm' ) {
        if ( blessed($value) && $value->isa('DateTime::Duration') ) {
            return $value->seconds;
        }
        elsif ( blessed($value) && $value->isa('DateTime') ) {
            return $value->epoch;
        }
        elsif ( looks_like_number($value) ) {
            return int $value;
        }
        else {
            confess "$class: Input value for $col is not an int or DateTime.";
        }
    }
    # put other decodes here
    else {
        # nothing for now
        return $value;
    }
}

=item column_pseudotype() [CLASS METHOD]

Returns the "pseudo type" for the column name passed in.    This is the type
defined in the class at initialization that is used by the DDL generator to
create RDBMS-specific types.

 my $type = $class->column_pseudotype( $col );

=cut

sub column_pseudotype {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $column = shift;
    return $classes{$class}->{columns}{$column}->[0];
}

=item primary_key_query() [CLASS METHOD]

Returns a string containing a query fragment that can be placed after WHERE or AND.

 print DBIx::Snug::Client->primary_key_query, "\n";
 > client_id = ?

 my $pk_query = $self->primary_key_query;
 my $sth = $dbh->prepare( "SELECT foo FROM bar WHERE $pk_query" );
 $sth->execute( $self->primary_key_values );
 ...

=cut

sub primary_key_query {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $pk = $classes{$class}->{primary_key};

    # add placeholders to the primary key column names then join with AND's
    my $pk_query = join( ' AND ', map { $_.'=?' } @$pk );

    return $pk_query;
}

=item primary_key_values() [OBJECT METHOD]

Returns the values for the primary key in the same order that the primary_key method
does.   This is used internally for generating database queries and goes well with
the primary_key_query method.

 my $table = $obj->table;
 my $pk_query = $obj->primary_key_query;

 my $sth = $dbh->prepare( "SELECT foo FROM $table WHERE $pk_query" );
 $sth->execute( $obj->primary_key_values );
 ...

=cut

sub primary_key_values {
    my $self = shift;
    my $class = blessed($self);
    confess "$self: Cannot call primary_key_values as a class method."
        unless $class;
    my @vals = map { $self->{$_} } @{ $classes{$class}->{primary_key} };
    return wantarray ? @vals : \@vals;
}

=item primary_key_args()

Returns the primary key in key, value pairs in one big list easy to pass to
other objects' new.

 # make a hashref
 my $pkargs = { $obj->primary_key_args };

 my %pkargs = $obj->primary_key_args;

 my $x = Foo::Bar->new(
     dbh => $dbh,
     some_id => 1,
     $foo->primary_key_args
 );

=cut

sub primary_key_args {
    my $self = shift;
    my $class = blessed($self);
    confess "$self: Cannot call primary_key_values as a class method."
        unless $class;
    return map { $_ => $self->{$_} } @{ $classes{$class}->{primary_key} };
}

=item has_foreign_key()

Returns the foreign key class for a given column name if it is a FK.

 if ( my $fkclass = $class->has_foreign_key("foo") ) {
     ...
 }

=cut

sub has_foreign_key {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $col = shift;

    my( $fk_class, $fk_col ) = (
        $classes{$class}->{columns}{$col}[2],
        $classes{$class}->{columns}{$col}[3]
    );

    if ( $fk_class && $fk_col ) {
        return $fk_class;
    }
    else {
        return undef;
    }
}

=item foreign_key()

Given a column, this returns a list containing the foreign key table,
column, and class referenced by the object this method is called on.

 my( $tbl, $col, $fk_class ) = My::Referencing::Class->foreign_key( 'foo' );
 print "Column foo in My::Referencing::Class references $col in table $tbl\n";

=cut

sub foreign_key {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $col = shift;
    my( $fk_class, $fk_col ) = (
        $classes{$class}->{columns}{$col}[2],
        $classes{$class}->{columns}{$col}[3]
    );

    confess "$class: Column '$col' does not have a foriegn key relationship."
        unless ( $fk_class && $fk_col );

    my $fk_table = $classes{$fk_class}->{table};

    return( $fk_table, $fk_col, $fk_class );
}

=item foreign_key_class()

This returns the class that represents a referenced column via a foreign key.

 my $fk_class = $obj->foreign_key_class( "fk_item_id" );
 my $fk_obj = $fk_class->new( fk_item_id => $obj->fk_item_id );

=cut

sub foreign_key_class {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $col = shift;
    my( $fk_class, $fk_col ) = (
        $classes{$class}->{columns}{$col}[2],
        $classes{$class}->{columns}{$col}[3]
    );

    confess "$class: Column '$col' does not have a foriegn key relationship."
        unless ( $fk_class && $fk_col );

    return $fk_class;
}

=item foreign_key_classes()

Returns a list of classes that $this has references to.

 my @fk_classes = $class->foreign_key_classes;

=cut

sub foreign_key_classes {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my %fk_classes;
    foreach my $col ( $class->all_columns ) {
        if ( $class->has_foreign_key( $col ) ) {
            my $fk_class = $class->foreign_key_class( $col );
            $fk_classes{$fk_class} = $col;
        }
    }
    return keys %fk_classes;
}

=item foreign_key_columns()

Returns a list of columns that are foreign keys.

 my @fks = $class->foreign_key_columns;

=cut

sub foreign_key_columns {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my @cols;
    foreach my $col ( $class->all_columns ) {
        if ( $class->has_foreign_key( $col ) ) {
            push @cols, $col;
        }
    }
    return @cols;
}

=item add_class_definition() [CLASS METHOD]

Use setup(), documented below.

=cut

sub add_class_definition {
    my( $class, %args ) = @_;

    # make sure the important bits are present and set up properly
    die "Cannot call add_class_definition() on an object."
        if ( ref $class );
    die "Must provide a 'table' element for $class."
        unless $args{table};
    die "Must provide a 'primary_key' element for $class."
        unless $args{primary_key};
    die "'primary_key' in $class must be an ARRAYREF."
        unless ( ref($args{primary_key}) eq 'ARRAY' );
    die "Must provide a 'columns' element for $class and it must be a HASH reference."
        unless ( ref($args{columns}) eq 'HASH' );

    foreach my $pk ( @{ $args{primary_key} } ) {
        die "Primary key '$pk' must also be listed in columns hash."
            unless ( $args{columns}->{$pk} );
    }

    # install it - this does nothing until init() is called
    $classes{$class} = \%args;
}

=item get_class_definition()

Returns a reference to the class definition in DBIx::Snug.   Note that it
returns a REFERENCE, so be wary of changing data elements ;)

 use DBIx::Snug::Code;
 use Data::Dumper;
 my $class = 'DBIx::Snug::Code';
 my $struct = $class->get_class_definition;
 print Dumper( $struct );

=cut

sub get_class_definition {
    my $class = ref($_[0]) ? ref(shift) : shift;
    return $classes{$class};
}


=item setup() [CLASS METHOD]

Pass in the same data as add_class_definition.   This will do all of the setup in one call, though.   It also supports columns being an ARRAYREF so that table DDL is generated with the columns in the expected order.

 package Excellent;
 use base 'DBIx::Snug';

 Excellent->setup(
    table => 'tablename',
    primary_key => 'id',
    columns => [
        id  => [ 'int',  'sequence' ],
        foo => [ 'text', 'NULL' ],
        bar => [ 'bool', 'false' ]
    ]
 );

 # replaces
 Excellent->add_class_definition(
    table => 'tablename',
    primary_key => 'id',
    columns => {
        id  => [ 'int',  'sequence' ],
        foo => [ 'text', 'NULL' ],
        bar => [ 'bool', 'false' ]
    }
 );
 Excellent->init;

=cut

# Note: this detection runs once at compile-time
# if Tie::IxHash is not available, use the embedded Tie::InsertOrderHash
my $tieclass = 'DBIx::Snug::Tie::InsertOrderHash';
eval( 'use Tie::IxHash;' ); # see if it's available
unless ( $@ ) {
    $tieclass = 'Tie::IxHash';
}

sub setup {
    my( $class, %args ) = @_;
    
    # work around hash randomization by allowing arrays, too
    # the array is converted to a tied hash that maintains insertion order
    # see the detection code a few lines above
    if ( ref $args{columns} eq 'ARRAY' ) {
        my %cols;
        tie %cols, $tieclass;
        %cols = @{ $args{columns} };
        $args{columns} = \%cols;
    }

    $class->add_class_definition( %args );
    $class->init;
}

=item list_all_classes()

List all of the registered DBIx::Snug classes.

 my @classes = DBIx::Snug->list_all_classes;

=cut

sub list_all_classes {
    return sort keys %classes;
}

=item list_subclasses()

=cut

sub list_subclasses {
    my $class = blessed($_[0]) ? blessed(shift) : shift;

    if ( $class eq 'DBIx::Snug' ) {
        return keys %classes;
    }
    elsif ( exists $classes{$class} ) {
        my @subs;
        foreach my $sub ( keys %classes ) {
            foreach my $col ( values %{$classes{$sub}->{columns}} ) {
                next unless $col->[1] && $col->[2];
                if ( $col->[1] eq 'super' && $col->[2] eq $class ) {
                    push @subs, $sub;
                }
            }
        }
        return @subs;
    }
    else {
        confess "$class is not supported for this method.";
    }
}

=item _can()

A nasty version of UNIVERSAL::can() that does NOT traverse the object
heirarchy searching for the method.   It checks to see if a subroutine
of name passed in exists in the package it was called on, and that is all.

 croak "Ahh! Method $meth doesn't exist in $class!"
    unless ( $class->_can($meth) );

=cut

sub _can {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $sym = $class.'::'.$_[0];
    return undef unless defined *{$sym}{CODE};
    return 1;
}

=item truncate_table() [DANGEROUS, CLASS METHOD]

This is mainly intended for use in tests.   It deletes all rows from the
backend table of the class.   Foreign keys may blow up, etc..

 $class->truncate_table;

=cut

sub truncate_table {
    my $class = ref($_[0]) ? ref(shift) : shift;
    my $dbh = shift;

    my $query = "DELETE FROM " . $classes{$class}->{table};
    $dbh->do( $query );
    if ( $dbh->err ) { warn $dbh->errstr }
}

=item _dttm_in() [INTERNAL]

Takes an incoming date/time argument and makes sure it ends up
as a DateTime object.   Allows methods to take an object or epoch time.

 sub foo {
     my $self = shift;
     my $dttm = $self->_dttm_in( shift );
     ...
 }

=cut

sub _dttm_in {
    my( $self, $thing ) = @_;

    if ( !defined $thing ) {
        return undef;
    }
    # blessed() and looks_like_number() from Scalar::Util
    elsif ( blessed($thing) && $thing->isa('DateTime') ) {
        return $thing;
    }
    elsif ( looks_like_number($thing) ) {
        return DateTime->from_epoch(
            time_zone => 'UTC',
            epoch     => $thing
        );
    }
    else {
        confess "Can't do a thing with $thing.";
    }
}

=item _interval_in() [INTERNAL]

Takes an incoming interval argument and makes sure it ends up
as a DateTime::Duration object.   Allows methods to take a number of
seconds or an object.

 sub foo {
     my $self = shift;
     my $interval = $self->_interval_in( shift );
     ...
 }

=cut

sub _interval_in {
    my( $self, $thing ) = @_;
    my $type = blessed($thing);

    if ( !defined $thing ) {
        return undef;
    }
    # blessed() and looks_like_number() from Scalar::Util
    elsif ( $type && $thing->isa('DateTime::Duration') ) {
        return $thing;
    }
    elsif ( looks_like_number($thing) ) {
        return DateTime::Duration->new(
            seconds => $thing
        );
    }
    else {
        confess "Can't do a thing with $thing.";
    }
}

=back

=head1 FUNCTIONS, HACKS

=over 4

=item _dsecs() [INTERNAL, FUNCTION]

Converts a DateTime object to a number of seconds since midnight.   This
is also pushed into DateTime as the $dttm->dsecs() method whenever
DBIx::Snug is loaded.

 my $dsecs = _dsecs( $dttm_object );

=cut

sub _dsecs {
    my $dttm = shift;
    my $secs = $dttm->hour * 60 * 60;
    $secs   += $dttm->minute * 60;
    $secs   += $dttm->second;
    return $secs;
}

=item DateTime::descs()

Extends DateTime to have a dsecs() method which returns the number of seconds
that have elapsed since midnight.

=cut

sub DateTime::dsecs {
    my $self = shift;
    DBIx::Snug::_dsecs($self);
}

=back

=head1 WHY_ANOTHER_ORM

Yes, I've heard of DBIx::Class, Class::DBI and other ORM tools for perl.
This module only took a couple hours to write and it has the following advantages over
Class::DBI/DBIx::Class:

 * much smaller code size
 * no huge graph of CPAN dependencies
 * no problems with mod_perl
 * DBIx::Snug::DDL generates multi-database DDL without any extra work

Disadvantages (that I know of):

 * must be maintained by me
 * doesn't tie into all the neat toys Class:DBI has on CPAN

=head1 TODO

 * port to other databases like Postgres and Oracle

=head1 BUGS

See AUTHOR.

=head1 SEE ALSO

 DBIx::Snug::Search
 DBIx::Snug::Join
 DBIx::Snug::View
 DBIx::Snug::DDL
 DBIx::Snug::MySQL
 DBIx::Snug::SQLite

=head1 AUTHORS

 Al Tobey <tobert@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2006-2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

DBIx::Snug::Tie::InsertOrderHash is an embedded version of Tie::InsertOrderHash
which is Artistic/GPL2.

You may distribute under the terms of either the GNU General Public License or
the Artistic License, as specified in the Perl README file.

http://search.cpan.org/dist/Tie-InsertOrderHash/InsertOrderHash.pm

=cut

1;

# Ripped from CPAN:
# The only thing I changed here was whitespace and the package.
# It's incredibly dense, but works fine and removes an external
# dependency (Tie::IxHash).
#
# This section is licensed Artistic/GPL:
# You may distribute under the terms of either the GNU General Public License
# or the Artistic License, as specified in the Perl README file.
#
# http://search.cpan.org/dist/Tie-InsertOrderHash/InsertOrderHash.pm
package DBIx::Snug::Tie::InsertOrderHash;

use strict;
use warnings;

our $VERSION = '0.01';

use base qw(Tie::Hash);

sub TIEHASH  {
    my $c = shift;
	bless [[@_[grep { $_ % 2 == 0 } (0..$#_)]], {@_}, 0], $c;
}

sub STORE {
    @{$_[0]->[0]} = grep { $_ ne $_[1] } @{$_[0]->[0]};
	push @{$_[0]->[0]}, $_[1];
	$_[0]->[2] = -1;
	$_[0]->[1]->{$_[1]} = $_[2];
}

sub FETCH { $_[0]->[1]->{$_[1]} }

sub FIRSTKEY {
    return wantarray ? () : undef
        unless exists $_[0]->[0]->[$_[0]->[2] = 0];
	my $key = $_[0]->[0]->[0];
	return wantarray ? ($key, $_[0]->[1]->{$key}) : $key 
}

# Guard against deletion (see perldoc -f each)
sub NEXTKEY {
    my $i = $_[0]->[2];
	return wantarray ? () : undef unless exists $_[0]->[0]->[$i];
	if ($_[0]->[0]->[$i] eq $_[1]) {
	    $i = ++$_[0]->[2] ;
		return wantarray ? () : undef
		unless exists $_[0]->[0]->[$i];
	}
	my $key = ${$_[0]->[0]}[$i];
	return wantarray ? ($key, $_[0]->[1]->{$key}) : $key
}

sub EXISTS { exists $_[0]->[1]->{$_[1]} }

sub DELETE {
    @{$_[0]->[0]} = grep { $_ ne $_[1] } @{$_[0]->[0]};
	CORE::delete $_[0]->[1]->{$_[1]};
}

sub CLEAR {
    @{$_[0]->[0]} = ();
	%{$_[0]->[1]} = ();
}

1;

# vim: et ts=4 sw=4 ai smarttab
