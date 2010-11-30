package DBIx::Snug::MySQL::InformationSchema::TableConstraints;

###########################################################################
#                                                                         #
# DBIx::Snug::MySQL::InformationSchema::TableConstraints                  #
# Copyright 2010, Albert P. Tobey <tobert@gmail.com>                      #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
###########################################################################

use strict;
use warnings;
use base 'DBIx::Snug';

=head1 NAME

DBIx::Snug::MySQL::InformationSchema::TableConstraints

=head1 DESCRIPTION

A very simple DBIx::Snug subclass for querying the MySQL INFORMATION_SCHEMA.

=head1 TABLE

 +--------------------+--------------+------+-----+---------+-------+
 | Field              | Type         | Null | Key | Default | Extra |
 +--------------------+--------------+------+-----+---------+-------+
 | CONSTRAINT_CATALOG | varchar(512) | YES  |     | NULL    |       | 
 | CONSTRAINT_SCHEMA  | varchar(64)  | NO   |     |         |       | 
 | CONSTRAINT_NAME    | varchar(64)  | NO   |     |         |       | 
 | TABLE_SCHEMA       | varchar(64)  | NO   |     |         |       | 
 | TABLE_NAME         | varchar(64)  | NO   |     |         |       | 
 | CONSTRAINT_TYPE    | varchar(64)  | NO   |     |         |       | 
 +--------------------+--------------+------+-----+---------+-------+

=cut

__PACKAGE__->setup(
    table => 'table_constraints',
    primary_key => ['table_schema','table_name'],
    columns => [
        constraint_catalog => [ 'varchar(512)', 'NULL' ],
        constraint_schema  => [ 'varchar(64)',  undef  ],
        constraint_name    => [ 'varchar(64)',  undef  ],
        table_schema       => [ 'varchar(512)', undef  ],
        table_name         => [ 'varchar(512)', undef  ],
        constraint_type    => [ 'varchar(64)',  undef  ]
]
);

1;

__END__

=head1 AUTHORS

 Al Tobey <tobert@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

=cut

