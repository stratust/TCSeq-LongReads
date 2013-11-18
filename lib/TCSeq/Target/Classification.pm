use MooseX::Declare;
use Method::Signatures::Modifiers;

class TCSeq::Target::Classification {

    use MooseX::Attribute::Dependent;

    has 'is_translocation' => (
        is            => 'rw',
        isa           => 'Bool',
        dependency => None['is_rerrangement'],
    );

    has 'is_rearrangement' => (
        is            => 'rw',
        isa           => 'Bool',
        dependency => None['is_translocation'],
    );

    has 'is_inversion' => (
        is            => 'rw',
        isa           => 'Bool',
    );

    has 'bait_is_blunt' => (
        is            => 'rw',
        isa           => 'Bool',
        dependency => None['bait_deletion_size'],
    );

    has 'target_is_blunt' => (
        is            => 'rw',
        isa           => 'Bool',
        dependency => None['target_deletion_size','is_translocation'],
    );


    has 'bait_deletion_size' => (
        is            => 'rw',
        isa           => 'Int',
        dependency => None['is_blunt'],
        predicate => 'has_bait_deletion',
    );

    # target deletion will be accepted only for rearrangements
    has 'target_deletion_size' => (
        is            => 'rw',
        isa           => 'Int',
        dependency => None['target_is_blunt','is_translocation'],
        predicate => 'has_target_deletion',
    );

    has 'insertion_size' => (
        is            => 'rw',
        isa           => 'Int',
        predicate => 'has_insertion'
    );

    has 'microhomology_size' => (
        is            => 'rw',
        isa           => 'Int',
        predicate => 'has_microhomology'
    );
    
}
