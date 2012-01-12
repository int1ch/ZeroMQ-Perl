use strict;
use Test::More;
use Test::Requires qw( Test::TCP );
use ZMQ qw(ZMQ_PUB ZMQ_SUB ZMQ_SNDMORE);
use Time::HiRes qw(usleep);

BEGIN {
    use_ok "ZMQ";
    use_ok "ZMQ::Constants", ":all";
    use_ok "ZMQ::Raw";
}

my $max = $ENV{ MSGCOUNT } || 100;
note "Using $max messages to test - set MSGCOUNT to a different number if you want to change this";

subtest 'high-level API' => sub {
    my $server = Test::TCP->new( code => sub {
        my $port = shift;
        my $ctxt = ZMQ::Context->new();
        my $sock = $ctxt->socket(ZMQ_PUB);
    
        note "Server Binding to port $port\n";
        $sock->bind("tcp://127.0.0.1:$port");
    
        note "Waiting on client to bind...";
        sleep 2;
        note "Server sending ordered data... (numbers 1..1000)";
        for my $c ( 0 .. ( $max - 1 ) ) {
            is $sock->send($c, -1, ZMQ_SNDMORE), length $c, "send OK";
        }
        is $sock->send("end", 3, 0), 3, "last send OK"; # end of data stream...
        $sock->close;
        note "Sent all messages";
        exit 0;
    } );

    my $port = $server->port;
    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket(ZMQ_SUB);

    $sock->connect("tcp://127.0.0.1:$port" );
    $sock->setsockopt(ZMQ_SUBSCRIBE, '');
    my $data = join '.', time(), $$, rand, {};

    my $msg;
    for my $cnt ( 0.. $max) { # ( $max - 1 ) ) {
        $msg = $sock->recvmsg();
        my $data = $msg->data;
        my $rcvmore = $sock->getsockopt(ZMQ_RCVMORE);
        if ($rcvmore) {
            is($data, $cnt, "Expected $cnt, got $data");
        } else {
            is($data, 'end', "Expected '', got $data");
            last;
        }
    } 

    $sock->setsockopt(ZMQ_LINGER, 0);
    note "Received all messages";
};

subtest 'low-level API' => sub {
    my $server = Test::TCP->new( code => sub {
        my $port = shift;
        my $ctxt = zmq_init();
        my $sock = zmq_socket($ctxt, ZMQ_PUB);

        note "Server Binding to port $port\n";
        zmq_bind($sock, "tcp://127.0.0.1:$port");
        note "Waiting on client to bind...";
        sleep 2;

        note "Server sending ordered data... (numbers 1..1000)";
        for my $c ( 0 .. ( $max - 1 ) ) {
            zmq_send($sock, $c, -1, ZMQ_SNDMORE);
        }
        zmq_send( $sock, "end", 3, 0 );
        note "Sent all messages";
        note "Server exiting...";
        exit 0;
    } );

    my $port = $server->port;
    my $ctxt = zmq_init();
    my $sock = zmq_socket($ctxt, ZMQ_SUB);

    note "Client connecting to port $port";
    zmq_connect($sock,"tcp://127.0.0.1:$port" );
    zmq_setsockopt($sock, ZMQ_SUBSCRIBE, '');

    note "Starting to receive data";
    for my $cnt ( 0 .. $max ) {
        my $rawmsg = zmq_recvmsg($sock);
        my $data = zmq_msg_data($rawmsg);
        if (zmq_getsockopt($sock, ZMQ_RCVMORE)) {
            is($data, $cnt, "Expected $cnt, got $data");
        }  else {
            is( $data, "end", "Done!" );
            last;
        }
    }
    zmq_setsockopt($sock, ZMQ_LINGER, 0);
    note "Received all messages";
};



done_testing;
