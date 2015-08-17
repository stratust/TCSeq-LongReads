use utf8;
package TCSeq::DB::Schema::Result::HotspotHasShear;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

TCSeq::DB::Schema::Result::HotspotHasShear

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<hotspot_has_shear>

=cut

__PACKAGE__->table("hotspot_has_shear");

=head1 ACCESSORS

=head2 hotspot_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 shear_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "hotspot_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "shear_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</hotspot_id>

=item * L</shear_id>

=back

=cut

__PACKAGE__->set_primary_key("hotspot_id", "shear_id");

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


# Created by DBIx::Class::Schema::Loader v0.07040 @ 2014-10-17 17:46:19
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:i39wPshf3URLK5cjXZJEXQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
