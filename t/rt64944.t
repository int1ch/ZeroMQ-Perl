# This test file is used in xt/rt64944.t, but is also in t/
# because it checks (1) failure cases in ZMQ_RCVMORE, and
# (2) shows how non-blocking recvmsg() should be handled

use strict;
use Test::More;
use Test::Requires qw( Test::TCP );

BEGIN {
    use_ok "ZMQ";
    use_ok "ZMQ::Raw";
    use_ok "ZMQ::Constants", ":all";
}

subtest 'blocking recvmsg' => sub {
    my $server = Test::TCP->new(code => sub {
        my $port = shift;
        note "START blocking recvmsg server on port $port";
        my $ctxt = ZMQ::Context->new();
        my $sock = $ctxt->socket(ZMQ_PUB);

        $sock->bind("tcp://127.0.0.1:$port");
        sleep 2;
        for (1..10) {
            $sock->send($_);
        }
        sleep 2;
        note "END blocking recvmsg server";
        $sock->close;

        exit 0;
    });

    my $port = $server->port;
    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket(ZMQ_SUB);

    note "blocking recvmsg client connecting to port $port";
    $sock->connect("tcp://127.0.0.1:$port" );
    $sock->setsockopt(ZMQ_SUBSCRIBE, '');

    for(1..10) {
        my $msg = $sock->recvmsg();
        is $msg->data(), $_;
    }
};

subtest 'non-blocking recvmsg (fail)' => sub {
    my $server = Test::TCP->new(code => sub {
        my $port = shift;
        my $ctxt = ZMQ::Context->new();
        my $sock = $ctxt->socket(ZMQ_PUB);
    
        $sock->bind("tcp://127.0.0.1:$port");
        sleep 2;
        for (1..10) {
            $sock->send($_);
        }
        sleep 2;
        exit 0;
    } );

    my $port = $server->port;

    note "non-blocking client connecting to port $port";
    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket(ZMQ_SUB);

    $sock->connect("tcp://127.0.0.1:$port" );
    $sock->setsockopt(ZMQ_SUBSCRIBE, '');

    for(1..10) {
        my $msg = $sock->recvmsg(ZMQ_RCVMORE); # most of this call should really fail
    }
    ok(1); # dummy - this is just here to find leakage
};

# Code excericising zmq_poll to do non-blocking recvmsg()
subtest 'non-blocking recvmsg (success)' => sub {
    my $server = Test::TCP->new( code => sub {
        my $port = shift;
        my $ctxt = ZMQ::Context->new();
        my $sock = $ctxt->socket(ZMQ_PUB);

        $sock->bind("tcp://127.0.0.1:$port");
        sleep 2;
        for (1..10) {
            $sock->send($_);
        }
        sleep 2;
        exit 0;
    } );

    my $port = $server->port;
    my $ctxt = zmq_init();
    my $sock = zmq_socket( $ctxt, ZMQ_SUB);

    zmq_connect( $sock, "tcp://127.0.0.1:$port" );
    zmq_setsockopt( $sock, ZMQ_SUBSCRIBE, '');
    my $timeout = time() + 5;
    my $recvmsgd = 0;
    while ( $timeout > time() && $recvmsgd < 10 ) {
        zmq_poll( [ {
            socket => $sock,
            events => ZMQ_POLLIN,
            callback => sub {
                while (my $msg = zmq_recvmsg( $sock, ZMQ_RCVMORE)) {
                    is ( zmq_msg_data( $msg ), $recvmsgd + 1 );
                    $recvmsgd++;
                }
            }
        } ], 1000000 ); # timeout in microseconds, so this is 1 sec
    }
    is $recvmsgd, 10, "got all messages";
};
    
# Code excercising AnyEvent + ZMQ_FD to do non-blocking recvmsg
if ($^O ne 'MSWin32' && eval { require AnyEvent } && ! $@) {
    AnyEvent->import; # want AE namespace

    my $server = Test::TCP->new( code => sub {
        my $port = shift;
        my $ctxt = ZMQ::Context->new();
        my $sock = $ctxt->socket(ZMQ_PUB);

        $sock->bind("tcp://127.0.0.1:$port");
        sleep 2;
        for (1..10) {
            $sock->send($_);
        }
        sleep 10;
    } );

    my $port = $server->port;
    my $ctxt = zmq_init();
    my $sock = zmq_socket( $ctxt, ZMQ_SUB);

    zmq_connect( $sock, "tcp://127.0.0.1:$port" );
    zmq_setsockopt( $sock, ZMQ_SUBSCRIBE, '');
    my $timeout = time() + 30;
    my $recvmsgd = 0;
    my $cv = AE::cv();
    my $t;
    my $fh = zmq_getsockopt( $sock, ZMQ_FD );
    my $w; $w = AE::io( $fh, 0, sub {
        while (my $msg = zmq_recvmsg( $sock, ZMQ_RCVMORE)) {
            is ( zmq_msg_data( $msg ), $recvmsgd + 1 );
            $recvmsgd++;
            if ( $recvmsgd >= 10 ) {
                undef $t;
                undef $w;
                $cv->send;
            }
        }
    } );
    $t = AE::timer( 30, 1, sub {
        undef $t;
        undef $w;
        $cv->send;
    } );
    $cv->recv;
    is $recvmsgd, 10, "got all messages";
}

done_testing;
