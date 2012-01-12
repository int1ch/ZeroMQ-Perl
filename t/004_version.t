use strict;
use Test::More;

use_ok "ZMQ";

{
    my $version = ZMQ::version();
    ok $version;
    like $version, qr/^\d+\.\d+\.\d+$/, "dotted version string";

    my ($major, $minor, $patch) = ZMQ::version();

    is join('.', $major, $minor, $patch), $version, "list and scalar context";
}

done_testing;