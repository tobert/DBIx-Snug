package DBIx::Snug::MySQL::InformationSchema::Columns;

###########################################################################
#                                                                         #
# DBIx::Snug::MySQL::InformationSchema::Columns                           #
# Copyright 2010, Albert P. Tobey <tobert@gmail.com>                      #
# https://github.com/tobert/DBIx-Snug                                     #
#                                                                         #
###########################################################################

use strict;
use warnings;
use base 'DBIx::Snug';

=head1 NAME

DBIx::Snug::MySQL::InformationSchema::Columns

=head1 DESCRIPTION

A very simple DBIx::Snug subclass for querying the MySQL INFORMATION_SCHEMA.

=head1 TABLE

 +--------------------------+---------------------+------+-----+---------+-------+
 | Field                    | Type                | Null | Key | Default | Extra |
 +--------------------------+---------------------+------+-----+---------+-------+
 | TABLE_CATALOG            | varchar(512)        | YES  |     | NULL    |       | 
 | TABLE_SCHEMA             | varchar(64)         | NO   |     |         |       | 
 | TABLE_NAME               | varchar(64)         | NO   |     |         |       | 
 | COLUMN_NAME              | varchar(64)         | NO   |     |         |       | 
 | ORDINAL_POSITION         | bigint(21) unsigned | NO   |     | 0       |       | 
 | COLUMN_DEFAULT           | longtext            | YES  |     | NULL    |       | 
 | IS_NULLABLE              | varchar(3)          | NO   |     |         |       | 
 | DATA_TYPE                | varchar(64)         | NO   |     |         |       | 
 | CHARACTER_MAXIMUM_LENGTH | bigint(21) unsigned | YES  |     | NULL    |       | 
 | CHARACTER_OCTET_LENGTH   | bigint(21) unsigned | YES  |     | NULL    |       | 
 | NUMERIC_PRECISION        | bigint(21) unsigned | YES  |     | NULL    |       | 
 | NUMERIC_SCALE            | bigint(21) unsigned | YES  |     | NULL    |       | 
 | CHARACTER_SET_NAME       | varchar(32)         | YES  |     | NULL    |       | 
 | COLLATION_NAME           | varchar(32)         | YES  |     | NULL    |       | 
 | COLUMN_TYPE              | longtext            | NO   |     | NULL    |       | 
 | COLUMN_KEY               | varchar(3)          | NO   |     |         |       | 
 | EXTRA                    | varchar(27)         | NO   |     |         |       | 
 | PRIVILEGES               | varchar(80)         | NO   |     |         |       | 
 | COLUMN_COMMENT           | varchar(255)        | NO   |     |         |       | 
 +--------------------------+---------------------+------+-----+---------+-------+

=cut

__PACKAGE__->setup(
    table => 'columns',
    primary_key => ['table_schema','table_name','column_name'],
    columns => [
        table_catalog            => [ 'varchar(512)', 'NULL' ],
        table_schema             => [ 'varchar(64)',  undef  ],
        table_name               => [ 'varchar(64)',  undef  ],
        column_name              => [ 'varchar(64)',  undef  ],
        ordinal_position         => [ 'int',          0      ],
        column_default           => [ 'text',         'NULL' ],
        is_nullable              => [ 'varchar(3)',   'NULL' ],
        data_type                => [ 'varchar(64)',  'NULL' ],
        character_maximum_length => [ 'int',          'NULL' ],
        character_octet_length   => [ 'int',          'NULL' ],
        numeric_precision        => [ 'int',          'NULL' ],
        numeric_scale            => [ 'int',          'NULL' ],
        character_set_name       => [ 'varchar(32)',  'NULL' ],
        collation_name           => [ 'varchar(32)',  'NULL' ],
        column_type              => [ 'text',         undef  ],
        column_key               => [ 'varchar(3)',   undef  ],
        extra                    => [ 'varchar(27)',  undef  ],
        privileges               => [ 'varchar(80)',  undef  ],
        column_comment           => [ 'varchar(255)', undef  ]
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

