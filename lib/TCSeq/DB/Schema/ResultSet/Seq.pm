package TCSeq::DB::Schema::ResultSet::Seq;
use strict;
use warnings;
use base 'DBIx::Class::ResultSet';

TCSeq::DB::Schema::Result::Seq->has_many(
  "seq_has_shear",
  "TCSeq::DB::Schema::Result::ShearHasSeq",
  { "foreign.seq_id" => "self.seq_id" },
  { join_type => 'INNER'  } 
);

1;
