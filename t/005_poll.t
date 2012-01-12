use strict;
use Test::More;
use Test::Fatal;

BEGIN {
    use_ok "ZMQ::Raw";
    use_ok "ZMQ::Constants", ":all";
}

subtest 'basic poll with regular fd' => sub {
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

subtest 'poll with zmq sockets' => sub {
    my $ctxt = zmq_init();

    my $ipcpath = "inproc://polltest";

    my $rep = zmq_socket( $ctxt, ZMQ_PAIR );
    is zmq_bind( $rep, $ipcpath), 0, "bind ok to $ipcpath";

    my $req = zmq_socket( $ctxt, ZMQ_PAIR );
    is zmq_connect( $req, $ipcpath), 0, "connect ok $ipcpath";

    my $called = 0;
    is exception {
        my $data = "Test";
        if (! is zmq_send( $req, $data), length $data, "zmq_send ok") {
            die "Failed to send data";
        }

        zmq_send( $rep, "TEST");
        zmq_poll([
            {
                socket   => $rep,
                events   => ZMQ_POLLIN,
                callback => sub { $called++ }
            },
        ], 1) ;


        my $msg = zmq_recvmsg( $rep );
        if (ok $msg, "got message") {
            is zmq_msg_data($msg), $data, "data matches";
        }
    }, undef, "PollItem correctly handles callback";

    is $called, 1, "zmq_poll's call back was called once";
};

done_testing;