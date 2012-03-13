use strict;
use Test::Requires qw(
    Data::UUID
    Parallel::ForkManager
    Time::HiRes
    Test::SharedFork
);
use Test::TCP;
use Test::More;
use ZMQ::Raw;
use ZMQ::Constants qw(:all);

run();

sub run {
    my $max = 1_000; # 1_000_000;
    my $port = 9999;
    my @prefixes = (0..9, 'A'..'Z');

    note "Starting children";
    my $pm = Parallel::ForkManager->new(36);
    foreach my $prefix ( @prefixes ) {
        $pm->start() and next;
        eval { run_client( $port, $prefix ) };
        warn if $@;
        $pm->finish;
    }

    my $uuid = Data::UUID->new;
    my $ctxt = zmq_init();
    my $waiter = zmq_socket( $ctxt, ZMQ_REP );
    zmq_bind( $waiter, "tcp://127.0.0.1:$port" );

    my $pubsock = zmq_socket( $ctxt, ZMQ_PUB );
    my $pubport = Test::TCP::empty_port();
    zmq_bind( $pubsock, "tcp://127.0.0.1:$pubport" );

    my %waiting = map { ($_ => 1) } @prefixes;
    while ( 0 < scalar keys %waiting ) {
        my $id = zmq_msg_data(zmq_recvmsg( $waiter ));
        if ( delete $waiting{$id} ) {
            zmq_send( $waiter, $pubport );
        }
    }

    for ( 1 .. $max ) {
        my $data = $uuid->create_from_name_str(
            "pubsub_stress",
            join( ".",
                Time::HiRes::time(),
                {},
                rand(),
                $$
            )
        );
#        warn "sending $data";
        zmq_send( $pubsock, $data );
    }

    sleep 5;

    for my $prefix ( 0..9, 'A' ..'Z' ) {
        zmq_send( $pubsock, "$prefix-EXIT" );
    }

    note "Waiting for children to exit...";
    $pm->wait_all_children;

    note "All children done, doing cleanup";

    note "close waiter";
    zmq_close( $waiter );
    note "close pubsock";
    zmq_close( $pubsock );

    note "terminate";
    zmq_term($ctxt);

    done_testing();
}

sub run_client {
    my ($port, $prefix) = @_;

    my $ctxt = zmq_init();

    my $waiter = zmq_socket( $ctxt, ZMQ_REQ );
    zmq_connect( $waiter, "tcp://127.0.0.1:$port" );
    zmq_send( $waiter, $prefix );
    my $pubport = zmq_msg_data( zmq_recvmsg( $waiter ) );

    my $socket = zmq_socket( $ctxt, ZMQ_SUB );
    while ( zmq_connect( $socket, "tcp://127.0.0.1:$pubport" ) != 0 ) {
        note "Client ($prefix) ailed to connect, sleeping...";
        sleep 1;
    }
    note "Client ($prefix) connected";
    zmq_setsockopt( $socket, ZMQ_SUBSCRIBE, $prefix );
#    warn "subscribing to $prefix";

    my $loop = 1;
    while (1) {
        zmq_poll([ {
            socket => $socket,
            events => ZMQ_POLLIN,
            callback => sub {
                while (my $msg = zmq_recvmsg( $socket, ZMQ_RCVMORE )) {
                    my $data = zmq_msg_data( $msg );
                    note "client ($prefix), received message $data";
                    if ($data =~ /-EXIT$/ ) {
                        $loop = 0;
                    }
                }
            }
        } ], 1000000);
        last unless $loop;
    }

    note "clien ($prefix) done, doing cleanup";
    zmq_close( $waiter );
    zmq_close( $socket );
    zmq_term( $ctxt );
    ok(1, "client ($prefix) done" );
}

1;