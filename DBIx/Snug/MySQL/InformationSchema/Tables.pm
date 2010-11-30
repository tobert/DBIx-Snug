package DBIx::Snug::MySQL::InformationSchema::Tables;

###########################################################################
#                                                                         #
# DBIx::Snug::MySQL::InformationSchema::Tables                            #
# Copyright 2010, Albert P. Tobey <tobert@gmail.com>                      #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
###########################################################################

use strict;
use warnings;
use base 'DBIx::Snug';

=head1 NAME

DBIx::Snug::MySQL::InformationSchema::Tables

=head1 DESCRIPTION

A very simple DBIx::Snug subclass for querying the MySQL INFORMATION_SCHEMA.

=head1 TABLE

 +-----------------+---------------------+------+-----+---------+-------+
 | Field           | Type                | Null | Key | Default | Extra |
 +-----------------+---------------------+------+-----+---------+-------+
 | TABLE_CATALOG   | varchar(512)        | YES  |     | NULL    |       | 
 | TABLE_SCHEMA    | varchar(64)         | NO   |     |         |       | 
 | TABLE_NAME      | varchar(64)         | NO   |     |         |       | 
 | TABLE_TYPE      | varchar(64)         | NO   |     |         |       | 
 | ENGINE          | varchar(64)         | YES  |     | NULL    |       | 
 | VERSION         | bigint(21) unsigned | YES  |     | NULL    |       | 
 | ROW_FORMAT      | varchar(10)         | YES  |     | NULL    |       | 
 | TABLE_ROWS      | bigint(21) unsigned | YES  |     | NULL    |       | 
 | AVG_ROW_LENGTH  | bigint(21) unsigned | YES  |     | NULL    |       | 
 | DATA_LENGTH     | bigint(21) unsigned | YES  |     | NULL    |       | 
 | MAX_DATA_LENGTH | bigint(21) unsigned | YES  |     | NULL    |       | 
 | INDEX_LENGTH    | bigint(21) unsigned | YES  |     | NULL    |       | 
 | DATA_FREE       | bigint(21) unsigned | YES  |     | NULL    |       | 
 | AUTO_INCREMENT  | bigint(21) unsigned | YES  |     | NULL    |       | 
 | CREATE_TIME     | datetime            | YES  |     | NULL    |       | 
 | UPDATE_TIME     | datetime            | YES  |     | NULL    |       | 
 | CHECK_TIME      | datetime            | YES  |     | NULL    |       | 
 | TABLE_COLLATION | varchar(32)         | YES  |     | NULL    |       | 
 | CHECKSUM        | bigint(21) unsigned | YES  |     | NULL    |       | 
 | CREATE_OPTIONS  | varchar(255)        | YES  |     | NULL    |       | 
 | TABLE_COMMENT   | varchar(80)         | NO   |     |         |       | 
 +-----------------+---------------------+------+-----+---------+-------+

=cut

__PACKAGE__->setup(
    table => 'tables',
    primary_key => ['table_schema','table_name'],
    columns => [
        table_catalog   => [ 'varchar(512)', 'NULL' ],
        table_schema    => [ 'varchar(512)', undef  ],
        table_name      => [ 'varchar(512)', undef  ],
        table_type      => [ 'varchar(512)', undef  ],
        engine          => [ 'varchar(512)', 'NULL' ],
        version         => [ 'varchar(512)', 'NULL' ],
        row_format      => [ 'varchar(512)', 'NULL' ],
        table_rows      => [ 'varchar(512)', 'NULL' ],
        avg_row_length  => [ 'varchar(512)', 'NULL' ],
        data_length     => [ 'varchar(512)', 'NULL' ],
        max_data_length => [ 'varchar(512)', 'NULL' ],
        index_length    => [ 'varchar(512)', 'NULL' ],
        data_free       => [ 'varchar(512)', 'NULL' ],
        auto_increment  => [ 'varchar(512)', 'NULL' ],
        create_time     => [ 'varchar(512)', 'NULL' ],
        update_time     => [ 'varchar(512)', 'NULL' ],
        check_time      => [ 'varchar(512)', 'NULL' ],
        table_collation => [ 'varchar(512)', 'NULL' ],
        checksum        => [ 'varchar(512)', 'NULL' ],
        create_options  => [ 'varchar(512)', 'NULL' ],
        table_comment   => [ 'varchar(512)', ''     ]
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

