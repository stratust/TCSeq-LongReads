use utf8;
package TCSeq::DB::Schema::Result::MicrohomologyBaitAlignment;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::MicrohomologyBaitAlignment

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<microhomology_bait_alignment>

=cut

__PACKAGE__->table("microhomology_bait_alignment");

=head1 ACCESSORS

=head2 seq_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 hotspot_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 microhomology_bait_reference_sequence

  data_type: 'text'
  is_nullable: 0

=head2 microhomology_bait_match_string

  data_type: 'text'
  is_nullable: 0

=head2 microhomology_bait_query_sequence

  data_type: 'text'
  is_nullable: 0

=head2 microhomology_bait_reference_start

  data_type: 'integer'
  is_nullable: 0

=head2 microhomology_bait_reference_end

  data_type: 'integer'
  is_nullable: 0

=head2 microhomology_bait_reference_strand

  data_type: 'varchar'
  is_nullable: 0
  size: 1

=head2 microhomology_bait_query_start

  data_type: 'integer'
  is_nullable: 0

=head2 microhomology_bait_query_end

  data_type: 'integer'
  is_nullable: 0

=head2 microhomology_bait_query_strand

  data_type: 'varchar'
  is_nullable: 0
  size: 1

=head2 microhomology_target_reference_sequence

  data_type: 'text'
  is_nullable: 1

=head2 microhomology_target_match_string

  data_type: 'text'
  is_nullable: 1

=head2 microhomology_target_query_sequence

  data_type: 'text'
  is_nullable: 1

=head2 microhomology_target_reference_genomic_position

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 microhomology_target_reference_start

  data_type: 'integer'
  is_nullable: 1

=head2 microhomology_target_reference_end

  data_type: 'integer'
  is_nullable: 1

=head2 microhomology_target_reference_strand

  data_type: 'varchar'
  is_nullable: 1
  size: 1

=head2 microhomology_target_query_start

  data_type: 'integer'
  is_nullable: 1

=head2 microhomology_target_query_end

  data_type: 'integer'
  is_nullable: 1

=head2 microhomology_target_query_strand

  data_type: 'varchar'
  is_nullable: 1
  size: 1

=head2 microhomology_size

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 microhomology_insertion_size

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "seq_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "hotspot_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "microhomology_bait_reference_sequence",
  { data_type => "text", is_nullable => 0 },
  "microhomology_bait_match_string",
  { data_type => "text", is_nullable => 0 },
  "microhomology_bait_query_sequence",
  { data_type => "text", is_nullable => 0 },
  "microhomology_bait_reference_start",
  { data_type => "integer", is_nullable => 0 },
  "microhomology_bait_reference_end",
  { data_type => "integer", is_nullable => 0 },
  "microhomology_bait_reference_strand",
  { data_type => "varchar", is_nullable => 0, size => 1 },
  "microhomology_bait_query_start",
  { data_type => "integer", is_nullable => 0 },
  "microhomology_bait_query_end",
  { data_type => "integer", is_nullable => 0 },
  "microhomology_bait_query_strand",
  { data_type => "varchar", is_nullable => 0, size => 1 },
  "microhomology_target_reference_sequence",
  { data_type => "text", is_nullable => 1 },
  "microhomology_target_match_string",
  { data_type => "text", is_nullable => 1 },
  "microhomology_target_query_sequence",
  { data_type => "text", is_nullable => 1 },
  "microhomology_target_reference_genomic_position",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "microhomology_target_reference_start",
  { data_type => "integer", is_nullable => 1 },
  "microhomology_target_reference_end",
  { data_type => "integer", is_nullable => 1 },
  "microhomology_target_reference_strand",
  { data_type => "varchar", is_nullable => 1, size => 1 },
  "microhomology_target_query_start",
  { data_type => "integer", is_nullable => 1 },
  "microhomology_target_query_end",
  { data_type => "integer", is_nullable => 1 },
  "microhomology_target_query_strand",
  { data_type => "varchar", is_nullable => 1, size => 1 },
  "microhomology_size",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "microhomology_insertion_size",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</seq_id>

=item * L</hotspot_id>

=back

=cut

__PACKAGE__->set_primary_key("seq_id", "hotspot_id");

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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NtSJ5MWHdqwKC8g/r23VAg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
