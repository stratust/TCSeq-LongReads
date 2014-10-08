use utf8;
package TCSeq::DB::Schema::Result::Library;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::Library

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<library>

=cut

__PACKAGE__->table("library");

=head1 ACCESSORS

=head2 library_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 library_name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "library_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "library_name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</library_id>

=back

=cut

__PACKAGE__->set_primary_key("library_id");

=head1 RELATIONS

=head2 breakpoints

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::Breakpoint>

=cut

__PACKAGE__->has_many(
  "breakpoints",
  "TCSeq::DB::Schema::Result::Breakpoint",
  { "foreign.library_id" => "self.library_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 hotspots

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::Hotspot>

=cut

__PACKAGE__->has_many(
  "hotspots",
  "TCSeq::DB::Schema::Result::Hotspot",
  { "foreign.library_id" => "self.library_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 seqs

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::Seq>

=cut

__PACKAGE__->has_many(
  "seqs",
  "TCSeq::DB::Schema::Result::Seq",
  { "foreign.library_id" => "self.library_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 shears

Type: has_many

Related object: L<TCSeq::DB::Schema::Result::Shear>

=cut

__PACKAGE__->has_many(
  "shears",
  "TCSeq::DB::Schema::Result::Shear",
  { "foreign.library_id" => "self.library_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2014-10-06 18:38:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:t/sQMTTCDpLLNCK9sabu6w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
