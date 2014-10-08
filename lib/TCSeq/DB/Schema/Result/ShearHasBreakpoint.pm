use utf8;
package TCSeq::DB::Schema::Result::ShearHasBreakpoint;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::ShearHasBreakpoint

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<shear_has_breakpoint>

=cut

__PACKAGE__->table("shear_has_breakpoint");

=head1 ACCESSORS

=head2 shear_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 breakpoint_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "shear_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "breakpoint_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</shear_id>

=item * L</breakpoint_id>

=back

=cut

__PACKAGE__->set_primary_key("shear_id", "breakpoint_id");

=head1 RELATIONS

=head2 breakpoint

Type: belongs_to

Related object: L<TCSeq::DB::Schema::Result::Breakpoint>

=cut

__PACKAGE__->belongs_to(
  "breakpoint",
  "TCSeq::DB::Schema::Result::Breakpoint",
  { breakpoint_id => "breakpoint_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
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


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2014-10-06 18:38:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0Ta2VNjJkwUriA34mXXYXw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
