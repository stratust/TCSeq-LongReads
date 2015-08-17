use utf8;
package TCSeq::DB::Schema::Result::Seq;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::Seq

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<seq>

=cut

__PACKAGE__->table("seq");

=head1 ACCESSORS

=head2 seq_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 read_name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 library_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "seq_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "read_name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "library_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</seq_id>

=back

=cut

__PACKAGE__->set_primary_key("seq_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<read_id_UNIQUE>

=over 4

=item * L</read_name>

=back

=cut

__PACKAGE__->add_unique_constraint("read_id_UNIQUE", ["read_name"]);

=head1 RELATIONS

=head2 bait_sequence

Type: might_have

Related object: L<TCSeq::DB::Schema::Result::BaitSequence>

=cut

__PACKAGE__->might_have(
  "bait_sequence",
  "TCSeq::DB::Schema::Result::BaitSequence",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 bait_sequence_softclipped

Type: might_have

Related object: L<TCSeq::DB::Schema::Result::BaitSequenceSoftclipped>

=cut

__PACKAGE__->might_have(
  "bait_sequence_softclipped",
  "TCSeq::DB::Schema::Result::BaitSequenceSoftclipped",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 breakpoint_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::BreakpointHasSeq>

=cut

__PACKAGE__->has_many(
  "breakpoint_has_seqs",
  "TCSeq::DB::Schema::Result::BreakpointHasSeq",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 insertion_defined_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::InsertionDefinedHasSeq>

=cut

__PACKAGE__->has_many(
  "insertion_defined_has_seqs",
  "TCSeq::DB::Schema::Result::InsertionDefinedHasSeq",
  { "foreign.seq_id" => "self.seq_id" },
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

=head2 microhomology_bait_alignments

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::MicrohomologyBaitAlignment>

=cut

__PACKAGE__->has_many(
  "microhomology_bait_alignments",
  "TCSeq::DB::Schema::Result::MicrohomologyBaitAlignment",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 microhomology_defined_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::MicrohomologyDefinedHasSeq>

=cut

__PACKAGE__->has_many(
  "microhomology_defined_has_seqs",
  "TCSeq::DB::Schema::Result::MicrohomologyDefinedHasSeq",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shear_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::ShearHasSeq>

=cut

__PACKAGE__->has_many(
  "shear_has_seqs",
  "TCSeq::DB::Schema::Result::ShearHasSeq",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 target_sequence

Type: might_have

Related object: L<TCSeq::DB::Schema::Result::TargetSequence>

=cut

__PACKAGE__->might_have(
  "target_sequence",
  "TCSeq::DB::Schema::Result::TargetSequence",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 target_sequence_softclipped

Type: might_have

Related object: L<TCSeq::DB::Schema::Result::TargetSequenceSoftclipped>

=cut

__PACKAGE__->might_have(
  "target_sequence_softclipped",
  "TCSeq::DB::Schema::Result::TargetSequenceSoftclipped",
  { "foreign.seq_id" => "self.seq_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 breakpoints

Type: many_to_many

Composing rels: L</breakpoint_has_seqs> -> breakpoint

=cut

__PACKAGE__->many_to_many("breakpoints", "breakpoint_has_seqs", "breakpoint");

=head2 insertions_defined

Type: many_to_many

Composing rels: L</insertion_defined_has_seqs> -> insertion_defined

=cut

__PACKAGE__->many_to_many(
  "insertions_defined",
  "insertion_defined_has_seqs",
  "insertion_defined",
);

=head2 microhomologies_defined

Type: many_to_many

Composing rels: L</microhomology_defined_has_seqs> -> microhomology_defined

=cut

__PACKAGE__->many_to_many(
  "microhomologies_defined",
  "microhomology_defined_has_seqs",
  "microhomology_defined",
);

=head2 shears

Type: many_to_many

Composing rels: L</shear_has_seqs> -> shear

=cut

__PACKAGE__->many_to_many("shears", "shear_has_seqs", "shear");


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Ubng+rYHa4+gX9s0q92axQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
