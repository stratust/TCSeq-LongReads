use utf8;
package TCSeq::DB::Schema::Result::MicrohomologyDefinedHasSeq;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::MicrohomologyDefinedHasSeq

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<microhomology_defined_has_seq>

=cut

__PACKAGE__->table("microhomology_defined_has_seq");

=head1 ACCESSORS

=head2 shear_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 hotspot_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 seq_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "shear_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "hotspot_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "seq_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</shear_id>

=item * L</hotspot_id>

=item * L</seq_id>

=back

=cut

__PACKAGE__->set_primary_key("shear_id", "hotspot_id", "seq_id");

=head1 RELATIONS

=head2 microhomology_defined

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::MicrohomologyDefined>

=cut

__PACKAGE__->belongs_to(
  "microhomology_defined",
  "TCSeq::DB::Schema::Result::MicrohomologyDefined",
  { hotspot_id => "hotspot_id", shear_id => "shear_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 seq

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::Seq>

=cut

__PACKAGE__->belongs_to(
  "seq",
  "TCSeq::DB::Schema::Result::Seq",
  { seq_id => "seq_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:huEcih01CEao5hHMfm/7ZQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
