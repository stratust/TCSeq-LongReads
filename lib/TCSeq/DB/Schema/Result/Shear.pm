use utf8;
package TCSeq::DB::Schema::Result::Shear;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::Shear

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<shear>

=cut

__PACKAGE__->table("shear");

=head1 ACCESSORS

=head2 shear_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 shear_name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 shear_chr

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 shear_start

  data_type: 'bigint'
  is_nullable: 0

=head2 shear_end

  data_type: 'bigint'
  is_nullable: 0

=head2 shear_strand

  data_type: 'varchar'
  is_nullable: 0
  size: 1

=head2 library_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "shear_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "shear_name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "shear_chr",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "shear_start",
  { data_type => "bigint", is_nullable => 0 },
  "shear_end",
  { data_type => "bigint", is_nullable => 0 },
  "shear_strand",
  { data_type => "varchar", is_nullable => 0, size => 1 },
  "library_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</shear_id>

=back

=cut

__PACKAGE__->set_primary_key("shear_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<shear_name_UNIQUE>

=over 4

=item * L</shear_name>

=back

=cut

__PACKAGE__->add_unique_constraint("shear_name_UNIQUE", ["shear_name"]);

=head1 RELATIONS

=head2 hotspot_has_shears

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::HotspotHasShear>

=cut

__PACKAGE__->has_many(
  "hotspot_has_shears",
  "TCSeq::DB::Schema::Result::HotspotHasShear",
  { "foreign.shear_id" => "self.shear_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 insertions_defined

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::InsertionDefined>

=cut

__PACKAGE__->has_many(
  "insertions_defined",
  "TCSeq::DB::Schema::Result::InsertionDefined",
  { "foreign.shear_id" => "self.shear_id" },
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

=head2 microhomologies_defined

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::MicrohomologyDefined>

=cut

__PACKAGE__->has_many(
  "microhomologies_defined",
  "TCSeq::DB::Schema::Result::MicrohomologyDefined",
  { "foreign.shear_id" => "self.shear_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shear_has_breakpoints

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::ShearHasBreakpoint>

=cut

__PACKAGE__->has_many(
  "shear_has_breakpoints",
  "TCSeq::DB::Schema::Result::ShearHasBreakpoint",
  { "foreign.shear_id" => "self.shear_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shear_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::ShearHasSeq>

=cut

__PACKAGE__->has_many(
  "shear_has_seqs",
  "TCSeq::DB::Schema::Result::ShearHasSeq",
  { "foreign.shear_id" => "self.shear_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 breakpoints

Type: many_to_many

Composing rels: L</shear_has_breakpoints> -> breakpoint

=cut

__PACKAGE__->many_to_many("breakpoints", "shear_has_breakpoints", "breakpoint");

=head2 hotspots

Type: many_to_many

Composing rels: L</hotspot_has_shears> -> hotspot

=cut

__PACKAGE__->many_to_many("hotspots", "hotspot_has_shears", "hotspot");

=head2 seqs

Type: many_to_many

Composing rels: L</shear_has_seqs> -> seq

=cut

__PACKAGE__->many_to_many("seqs", "shear_has_seqs", "seq");


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1nJ6TohD4XJq+mw2mMGmNw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
