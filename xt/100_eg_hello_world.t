use strict;
use Test::More;
use Test::TCP;
BEGIN {
    use_ok "ZMQ", qw(ZMQ_REQ ZMQ_REP);
}

my $server = Test::TCP->new( code => sub {
    my $port = shift;
    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket(ZMQ_REP);
    $sock->bind( "tcp://127.0.0.1:$port" );

    my $message = $sock->recvmsg();
    is $message->data, "hello", "server receives correct data";
    $sock->send("world");
    exit 0;
} );

my $port = $server->port;
my $ctxt = ZMQ::Context->new();
my $sock = $ctxt->socket(ZMQ_REQ);
$sock->connect( "tcp://127.0.0.1:$port" );
$sock->send("hello");

my $message = $sock->recvmsg();
is $message->data, "world", "client receives correct data";

done_testing;