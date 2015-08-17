use utf8;
package TCSeq::DB::Schema::Result::InsertionDefined;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::InsertionDefined

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<insertion_defined>

=cut

__PACKAGE__->table("insertion_defined");

=head1 ACCESSORS

=head2 shear_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 hotspot_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 insertion_size

  data_type: 'integer'
  is_nullable: 1

=head2 insertion_chr

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 insertion_start

  data_type: 'integer'
  is_nullable: 1

=head2 insertion_end

  data_type: 'integer'
  is_nullable: 1

=head2 insertion_strand

  data_type: 'varchar'
  is_nullable: 1
  size: 1

=head2 insertion_color

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=cut

__PACKAGE__->add_columns(
  "shear_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "hotspot_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "insertion_size",
  { data_type => "integer", is_nullable => 1 },
  "insertion_chr",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "insertion_start",
  { data_type => "integer", is_nullable => 1 },
  "insertion_end",
  { data_type => "integer", is_nullable => 1 },
  "insertion_strand",
  { data_type => "varchar", is_nullable => 1, size => 1 },
  "insertion_color",
  { data_type => "varchar", is_nullable => 1, size => 45 },
);

=head1 PRIMARY KEY

=over 4

=item * L</shear_id>

=item * L</hotspot_id>

=back

=cut

__PACKAGE__->set_primary_key("shear_id", "hotspot_id");

=head1 RELATIONS

=head2 hotspot

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::Hotspot>

=cut

__PACKAGE__->belongs_to(
  "hotspot",
  "TCSeq::DB::Schema::Result::Hotspot",
  { hotspot_id => "hotspot_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 insertion_defined_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::InsertionDefinedHasSeq>

=cut

__PACKAGE__->has_many(
  "insertion_defined_has_seqs",
  "TCSeq::DB::Schema::Result::InsertionDefinedHasSeq",
  {
    "foreign.hotspot_id" => "self.hotspot_id",
    "foreign.shear_id"   => "self.shear_id",
  },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shear

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::Shear>

=cut

__PACKAGE__->belongs_to(
  "shear",
  "TCSeq::DB::Schema::Result::Shear",
  { shear_id => "shear_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 seqs

Type: many_to_many

Composing rels: L</insertion_defined_has_seqs> -> seq

=cut

__PACKAGE__->many_to_many("seqs", "insertion_defined_has_seqs", "seq");


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KpBd4dX/Ifweu+REZlq2SQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
