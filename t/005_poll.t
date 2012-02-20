use strict;
use Test::More;
use Test::Fatal;
use Test::TCP;

BEGIN {
    use_ok "ZMQ::Raw";
    use_ok "ZMQ::Constants", ":all";
}

note 'basic poll with regular fd';
{
    SKIP: {
        skip "Can't poll using fds on Windows", 2 if ($^O eq 'MSWin32');
        is exception {
            my $called = 0;
            zmq_poll([
                {
                    fd       => fileno(STDOUT),
                    events   => ZMQ_POLLOUT,
                    callback => sub { $called++ }
                }
            ], 1);
            ok $called, "callback called";
        }, undef, "PollItem doesn't die";
    }
};

note 'poll with zmq sockets';
{
    my $data = join ".", $$, {}, rand();

    my $server = Test::TCP->new(code => sub {
        my $port = shift;
        my $ctxt = zmq_init();
        my $rep = zmq_socket( $ctxt, ZMQ_PAIR );
        is zmq_bind( $rep, "tcp://127.0.0.1:$port"), 0, "bind ok to 127.0.0.1:$port";

        my $called = 0;
        while (1) {
            my $rv = zmq_poll([
                {
                    socket   => $rep,
                    events   => ZMQ_POLLIN,
                    callback => sub { $called++ }
                },
            ], 1) ;
            if ($rv) {
                my $msg = zmq_recvmsg( $rep );
                if (ok $msg, "got message") {
                    is zmq_msg_data($msg), $data, "data matches";
                    zmq_send( $rep, "received" );
                    is $called, 1, "zmq_poll's call back was called once";
                }
            }
        }
        exit 1;
    } );

    my $port = $server->port;
    my $ctxt = zmq_init();
    my $req = zmq_socket( $ctxt, ZMQ_PAIR );
    is zmq_connect( $req, "tcp://127.0.0.1:$port"), 0, "connect ok 127.0.0.1:$port";

    my $called = 0;
    is exception {
        if (! is zmq_send( $req, $data), length $data, "zmq_send ok") {
            die "Failed to send data";
        }
        zmq_recvmsg( $req );
    }, undef, "PollItem correctly handles callback";
};

done_testing;