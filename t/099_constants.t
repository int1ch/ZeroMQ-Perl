use strict;
use Test::More;
use ZMQ::Constants ();

subtest 'Exports from ZMQ::Constants are actually available' => sub {
    can_ok( 'ZMQ::Constants', @ZMQ::Constants::EXPORT_OK );
};

subtest 'Constants defined in XS are available in exports' => sub {
    open my $fh, '<', "xs/const-xs.inc"
        or die "Could not open consts file xs/const-xs.inc: $!";
    my %symbols;
    while ( <$fh> ) {
        if (/^        (ZMQ_\S+) =/) {
            $symbols{$1}++;
        }
    }

    my %available = map { ($_ => 1) } @ZMQ::Constants::EXPORT_OK;

    foreach my $symbol ( sort keys %symbols ) {
        ok $available{$symbol}, "$symbol exists";
    }
};

done_testing;
