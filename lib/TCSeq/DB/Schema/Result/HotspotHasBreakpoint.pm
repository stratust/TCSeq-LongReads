use utf8;
package TCSeq::DB::Schema::Result::HotspotHasBreakpoint;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::HotspotHasBreakpoint

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<hotspot_has_breakpoint>

=cut

__PACKAGE__->table("hotspot_has_breakpoint");

=head1 ACCESSORS

=head2 hotspot_id

  data_type: 'integer'
  is_nullable: 0

=head2 breakpoint_id

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "hotspot_id",
  { data_type => "integer", is_nullable => 0 },
  "breakpoint_id",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</hotspot_id>

=item * L</breakpoint_id>

=back

=cut

__PACKAGE__->set_primary_key("hotspot_id", "breakpoint_id");


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2014-10-06 18:38:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:swJqhc2eQw2e39n8svmxvw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
