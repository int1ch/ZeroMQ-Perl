use strict;
use Test::More;
use Test::Requires qw( Test::TCP AnyEvent );

BEGIN {
    use_ok "ZMQ::Raw";
    use_ok "ZMQ::Constants", ":all";
}

my $server = Test::TCP->new(code => sub {
    my $port = shift;
    my $ctxt = zmq_init(1);
    my $sock = zmq_socket( $ctxt, ZMQ_REP );

    note "[Server] binding to tcp://127.0.0.1:$port";
    zmq_bind( $sock, "tcp://127.0.0.1:$port" );

    my $msg;
    if ( $^O eq 'MSWin32' ) {
        note "[Server] Win32 server, using zmq_poll";
        my $timeout = time() + 5;
        do {
            zmq_poll([
                {
                    socket   => $sock,
                    events   => ZMQ_POLLIN,
                    callback => sub {
                        $msg = zmq_recvmsg( $sock, ZMQ_RCVMORE );
                    }
                },
            ], 5);
        } while (! $msg && time < $timeout );
    } else {
        note "[Server] Using zmq_getsockopt + AE";
        my $cv = AE::cv;

        note "[Server] Extracting ZMQ_FD";
        my $fh = zmq_getsockopt( $sock, ZMQ_FD );

        note "[Server] Creating AE::io for fd";
        my $w; $w = AE::io $fh, 0, sub {
            if (my $msg = zmq_recvmsg( $sock, ZMQ_DONTWAIT )) {
                note " + Received message";
                undef $w;
                $cv->send( $msg );
            }
        };
        note "[Server] Waiting for event";
        $msg = $cv->recv;
    }

    if (ok defined $msg, "msg is defined") {
        zmq_send( $sock, zmq_msg_data( $msg ) );
    }
    exit 0;
});

my $port = $server->port;
my $ctxt = zmq_init(1);
my $sock = zmq_socket( $ctxt, ZMQ_REQ );

note "[Client] Connecting to tcp://127.0.0.1:$port";
zmq_connect( $sock, "tcp://127.0.0.1:$port" );
my $data = join '.', time(), $$, rand, {};
my $length = length($data);

note "Sending data to server";
my $sent = zmq_send( $sock, $data );
if (! is $sent, $length, "Properly sent $length bytes of message") {
    diag "Failed to send message... bailing out";
} else {
    note "Wait to receive message from server";
    my $msg = zmq_recvmsg( $sock );
    is $data, zmq_msg_data( $msg ), "Got back same data";
}

done_testing;
