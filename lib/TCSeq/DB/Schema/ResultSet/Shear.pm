package TCSeq::DB::Schema::ResultSet::Shear;
use strict;
use warnings;
use base 'DBIx::Class::ResultSet';

TCSeq::DB::Schema::Result::Shear->has_many(
  "shear_has_hotspot",
  "TCSeq::DB::Schema::Result::HotspotHasShear",
  { "foreign.shear_id" => "self.shear_id" },
  { join_type => 'INNER'  } 
);

1;
