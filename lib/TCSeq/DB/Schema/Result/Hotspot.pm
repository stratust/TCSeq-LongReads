use utf8;
package TCSeq::DB::Schema::Result::Hotspot;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::Hotspot

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<hotspot>

=cut

__PACKAGE__->table("hotspot");

=head1 ACCESSORS

=head2 hotspot_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 hotspot_name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 hotspot_dummy_name

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 hotspot_chr

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 hotspot_start

  data_type: 'bigint'
  is_nullable: 0

=head2 hotspot_end

  data_type: 'bigint'
  is_nullable: 0

=head2 library_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 hotspot_pvalue

  data_type: 'double precision'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "hotspot_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "hotspot_name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "hotspot_dummy_name",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "hotspot_chr",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "hotspot_start",
  { data_type => "bigint", is_nullable => 0 },
  "hotspot_end",
  { data_type => "bigint", is_nullable => 0 },
  "library_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "hotspot_pvalue",
  { data_type => "double precision", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</hotspot_id>

=back

=cut

__PACKAGE__->set_primary_key("hotspot_id");

=head1 RELATIONS

=head2 hotspot_has_shears

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::HotspotHasShear>

=cut

__PACKAGE__->has_many(
  "hotspot_has_shears",
  "TCSeq::DB::Schema::Result::HotspotHasShear",
  { "foreign.hotspot_id" => "self.hotspot_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 library

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::Library>

=cut

__PACKAGE__->belongs_to(
  "library",
  "TCSeq::DB::Schema::Result::Library",
  { library_id => "library_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 shears

Type: many_to_many

Composing rels: L</hotspot_has_shears> -> shear

=cut

__PACKAGE__->many_to_many("shears", "hotspot_has_shears", "shear");


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2014-10-06 18:38:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6V7wa0nrkWkDylTGendLhg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
