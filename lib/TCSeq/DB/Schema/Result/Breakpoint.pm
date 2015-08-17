use utf8;
package TCSeq::DB::Schema::Result::Breakpoint;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::Breakpoint

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<breakpoint>

=cut

__PACKAGE__->table("breakpoint");

=head1 ACCESSORS

=head2 breakpoint_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 breakpoint_name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 breakpoint_chr

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 breakpoint_start

  data_type: 'bigint'
  is_nullable: 0

=head2 breakpoint_end

  data_type: 'bigint'
  is_nullable: 0

=head2 breakpoint_strand

  data_type: 'varchar'
  is_nullable: 0
  size: 1

=head2 breakpoint_n_reads_used

  data_type: 'integer'
  is_nullable: 0

=head2 breakpoint_n_reads_aligned

  data_type: 'integer'
  is_nullable: 0

=head2 library_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "breakpoint_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "breakpoint_name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "breakpoint_chr",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "breakpoint_start",
  { data_type => "bigint", is_nullable => 0 },
  "breakpoint_end",
  { data_type => "bigint", is_nullable => 0 },
  "breakpoint_strand",
  { data_type => "varchar", is_nullable => 0, size => 1 },
  "breakpoint_n_reads_used",
  { data_type => "integer", is_nullable => 0 },
  "breakpoint_n_reads_aligned",
  { data_type => "integer", is_nullable => 0 },
  "library_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</breakpoint_name>

=item * L</library_id>

=back

=cut

__PACKAGE__->set_primary_key("breakpoint_name", "library_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<breakpoint_id_UNIQUE>

=over 4

=item * L</breakpoint_id>

=back

=cut

__PACKAGE__->add_unique_constraint("breakpoint_id_UNIQUE", ["breakpoint_id"]);

=head1 RELATIONS

=head2 breakpoint_has_seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::BreakpointHasSeq>

=cut

__PACKAGE__->has_many(
  "breakpoint_has_seqs",
  "TCSeq::DB::Schema::Result::BreakpointHasSeq",
  { "foreign.breakpoint_id" => "self.breakpoint_id" },
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

=head2 shear_has_breakpoints

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::ShearHasBreakpoint>

=cut

__PACKAGE__->has_many(
  "shear_has_breakpoints",
  "TCSeq::DB::Schema::Result::ShearHasBreakpoint",
  { "foreign.breakpoint_id" => "self.breakpoint_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 seqs

Type: many_to_many

Composing rels: L</breakpoint_has_seqs> -> seq

=cut

__PACKAGE__->many_to_many("seqs", "breakpoint_has_seqs", "seq");

=head2 shears

Type: many_to_many

Composing rels: L</shear_has_breakpoints> -> shear

=cut

__PACKAGE__->many_to_many("shears", "shear_has_breakpoints", "shear");


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7w61rBDKI3QcJJmME2hF6g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
