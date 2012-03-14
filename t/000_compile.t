use strict;
use Test::More;
use_ok "ZMQ";

my ($major, $minor, $patch) = ZMQ::version();
my $version = join('.', $major, $minor, $patch);

diag sprintf( 
    "\n   This is ZMQ.pm version %s\n   Linked against libzmq %s\n",
    $ZMQ::VERSION,
    $version, 
);

done_testing;
