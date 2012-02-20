use strict;
use Test::More;
use Test::SharedFork;
use File::Temp qw(tempdir);
use File::Spec;
use File::Path ();
use POSIX qw(SIGTERM);

BEGIN {
    use_ok "ZMQ", qw(ZMQ_REP ZMQ_REQ);
}

my $dir = tempdir();
my $id = join ".", $$, rand();
my $path = File::Spec->catfile( $dir, "$id.ipc" );
my $ipc  = "ipc://$path";

note "ipc $ipc";

my $pid = Test::SharedFork->fork();
if ($pid == 0) {
    my $ctxt = ZMQ::Context->new();

    my $child = $ctxt->socket( ZMQ_REQ );
    is $child->connect( $ipc ), 0, "connect to $ipc successful";
    ok $child->send( "Hello from $$" ) > 0, "send successful";

    sleep 6;
    note "client done, exiting";
    exit 0;
} elsif ($pid) {
    my $guard = bless {}, 'ZMQ::IPCTest::Guard';
    sub ZMQ::IPCTest::Guard::DESTROY {
        note "remove $dir";
        File::Path::remove_tree($dir);
    };

    my $ctxt = ZMQ::Context->new();
    my $parent_sock = $ctxt->socket(ZMQ_REP);
    $parent_sock->bind( $ipc );
    sleep 1;

    note "[Child] waiting for recvmsg";

    eval {
        local $SIG{ALRM} = sub { die "timed out" };
        alarm(5);

        my $msg = $parent_sock->recvmsg;
        note "[Child] verifying data in message";
        is $msg->data, "Hello from $pid", "message is the expected message";
    };
    ok !$@, "no errors: '$@'";

    alarm(0);

    kill SIGTERM(), $pid;

    waitpid $pid, 0;
} else {
    die "Could not fork: $!";
}

done_testing;
