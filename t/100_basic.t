use strict;
use warnings;
use File::Spec;

use Test::More;
use ZMQ qw/:all/;
use ZMQ::Raw;
use Storable qw/nfreeze thaw/;

$ENV{LC_ALL} = 'C';

subtest '(High-Level API) connect before server socket is bound (should fail)' => sub {
    my $cxt = ZMQ::Context->new;
    my $sock = $cxt->socket(ZMQ_PAIR); # Receiver

    # too early, server socket not created:
    my $client = $cxt->socket(ZMQ_PAIR);
    eval {
        $client->connect("inproc://myPrivateSocket");
    };
    like $@, qr/Connection refused/, "Connect should fail";
    like "$!", qr/Connection refused/;
};

subtest '(Low-Level API) connect before server socket is bound (should fail)' => sub {
    my $cxt = zmq_init();
    my $sock = zmq_socket($cxt, ZMQ_PAIR); # Receiver

    # too early, server socket not created:
    my $client = zmq_socket($cxt, ZMQ_PAIR);
    isnt zmq_connect($client, "inproc://myPrivateSocket"), 0, "Connect should fail";
    like "$!", qr/Connection refused/;
};

subtest 'basic inproc communication' => sub {
    my $cxt = ZMQ::Context->new;
    my $sock = $cxt->socket(ZMQ_PAIR); # Receiver
    eval {
        $sock->bind("inproc://myPrivateSocket");
    };
    ok !$@, "bind to inproc socket";

    my $client = $cxt->socket(ZMQ_PAIR); # sendmsger
    is $client->connect("inproc://myPrivateSocket"), 0, "Connect is successful";

    ok(!defined($sock->recvmsg(ZMQ_DONTWAIT())), "recvmsg before sendmsging anything should return nothing");

    {
    my $msg = ZMQ::Message->new("Talk to me");
    ok( $client->sendmsg( $msg ) > 0, "sendmsg");
    }

    # These tests are potentially dangerous when upgrades happen....
    # I thought of plain removing, but I'll leave it for now
    my ($major, $minor, $micro) = ZMQ::version();
    SKIP: {
        skip( "Need to be exactly zeromq 2.1.0", 3 )
            if ($major != 2 || $minor != 1 || $micro != 0);
        ok(!$sock->getsockopt(ZMQ_RCVMORE), "no ZMQ_RCVMORE set");
        ok($sock->getsockopt(ZMQ_AFFINITY) == 0, "no ZMQ_AFFINITY");
        ok($sock->getsockopt(ZMQ_RATE) == 100, "ZMQ_RATE is at default 100");
    }

    my $msg = $sock->recvmsg();
    if ( ok(defined $msg, "received defined msg")) {
        is($msg->data, "Talk to me", "received correct message");
    }

    # now test with objects, just for kicks.

    my $obj = {
        foo => 'bar',
        baz => [1..9],
        blah => 'blubb',
    };
    my $frozen = nfreeze($obj);
    ok($client->sendmsg( ZMQ::Message->new($frozen) ) >= 0, "sendmsg successful");
    $msg = $sock->recvmsg();
    ok(defined $msg, "received defined msg");
    isa_ok($msg, 'ZMQ::Message');
    is($msg->data(), $frozen, "got back same data");
    my $robj = thaw($msg->data);
    is_deeply($robj, $obj);
};


subtest '(High-Level) invalid bind' => sub {
    my $cxt = ZMQ::Context->new(0); # must be 0 theads for in-process bind
    my $sock = $cxt->socket(ZMQ_REP); # server like reply socket
    eval {
        $sock->bind("bulls***");
    };
    like $@, qr/Invalid argument/, "bind should fail";
    like "$!", qr/Invalid argument/;
};

subtest '(Low-Level) invalid bind' => sub {
    my $cxt = zmq_init();
    my $sock = zmq_socket($cxt, ZMQ_REP); # server like reply socket
    isnt zmq_bind($sock,"bulls***"), 0, "bind should fail";
    like "$!", qr/Invalid argument/;
};

done_testing;
