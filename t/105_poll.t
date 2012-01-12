use strict;
use warnings;

use Test::More;
use ZMQ qw/:all/;

subtest 'Poller with callback' => sub {
    my $ctxt = ZMQ::Context->new();
    my $rep = $ctxt->socket(ZMQ_PAIR);
    $rep->bind("inproc://polltest");
    my $req = $ctxt->socket(ZMQ_PAIR);
    $req->connect("inproc://polltest");

    my $called = 0;
    my $poller = ZMQ::Poller->new(
        {
            socket   => $rep,
            events   => ZMQ_POLLIN,
            callback => sub { $called++ }
        }
    );

    ok ! $poller->has_event(0), "has_event is false";

    $req->send( "Test" );
    $poller->poll(1);
    ok $poller->has_event(0), "has_event is true";

    is $called, 1, "... and the callback was called once";

    # repeat, to make sure event does not go away until picked up
    $poller->poll(1);
    ok $poller->has_event(0), "has_event should still be true, because we haven't received the message yet";

    my $msg = $rep->recvmsg();
    $poller->poll(1);
    ok ! $poller->has_event(0), "has_event is now false, because we picked the message up";
};

subtest 'Poller with no callback' => sub {
    my $ctxt = ZMQ::Context->new();
    my $rep = $ctxt->socket(ZMQ_PAIR);
    $rep->bind("inproc://polltest");
    my $req = $ctxt->socket(ZMQ_PAIR);
    $req->connect("inproc://polltest");

    my $poller = ZMQ::Poller->new(
        {
            socket   => $rep,
            events   => ZMQ_POLLIN,
        },
    );

    my $msg = $req->send("Test");
    $poller->poll(1);
    ok $poller->has_event(0);
};

subtest 'Poller with named poll item' => sub {
    my $ctxt = ZMQ::Context->new();
    my $rep = $ctxt->socket(ZMQ_PAIR);
    $rep->bind("inproc://polltest");
    my $req = $ctxt->socket(ZMQ_PAIR);
    $req->connect("inproc://polltest");

    my $poller = ZMQ::Poller->new(
        {
            name    => 'test_item',
            socket  => $rep,
            events  => ZMQ_POLLIN,
        },
    );

    ok ! $poller->has_event('test_item');

    $req->send("Test");
    $poller->poll(1);
    $rep->recvmsg();
    $poller->poll(1);

    ok ! $poller->has_event('test_item');
};

done_testing;
