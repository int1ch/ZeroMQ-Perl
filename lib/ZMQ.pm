package ZMQ;
use strict;
use ZMQ::Raw ();
BEGIN {
    our $VERSION = $ZMQ::Raw::VERSION;
    our @ISA = qw(Exporter);
}

use ZMQ::Context;
use ZMQ::Socket;
use ZMQ::Message;
use ZMQ::Poller;
use ZMQ::Constants;
use 5.008;
use Carp ();
use IO::Handle;

sub import {
    my $class = shift;
    if (@_) {
        ZMQ::Constants->export_to_level( 1, $class, @_ );
    }
}

1;
__END__

=head1 NAME

ZMQ - A libzmq wrapper for Perl

=head1 SYNOPSIS ( HIGH-LEVEL API )

    # echo server
    use ZMQ qw/:all/;

    my $cxt = ZMQ::Context->new;
    my $sock = $cxt->socket(ZMQ_REP);
    $sock->bind($addr);
  
    my $msg;
    foreach (1..$roundtrip_count) {
        $msg = $sock->recvmsg();
        $sock->sendmsg($msg);
    }

=head1 SYNOPSIS ( LOW-LEVEL API )

    use ZMQ::Raw;

    my $ctxt = zmq_init($threads);
    my $rv   = zmq_term($ctxt);

    my $rv   = zmq_connect( $socket, $where );
    my $rv   = zmq_bind( $socket, $where );
    my $msg  = zmq_msg_init();
    my $msg  = zmq_msg_init_size( $size );
    my $msg  = zmq_msg_init_data( $data );
    my $rv   = zmq_msg_close( $msg );
    my $rv   = zmq_msg_move( $dest, $src );
    my $rv   = zmq_msg_copy( $dest, $src );
    my $data = zmq_msg_data( $msg );
    my $size = zmq_msg_size( $msg);

    my $sock = zmq_socket( $ctxt, $type );
    my $rv   = zmq_close( $sock );
    my $rv   = zmq_setsockopt( $socket, $option, $value );
    my $val  = zmq_getsockopt( $socket, $option );
    my $rv   = zmq_bind( $sock, $addr );
    my $rv   = zmq_sendmsg( $sock, $msg, $flags );
    my $msg  = zmq_recvmsg( $sock, $flags );

=head1 INSTALLATION

If you have libzmq registered with pkg-config:

    perl Makefile.PL
    make 
    make test
    make install

If you don't have pkg-config, and libzmq is installed under /usr/local/libzmq:

    ZMQ_HOME=/usr/local/libzmq \
        perl Makefile.PL
    make
    make test
    make install

If you want to customize include directories and such:

    ZMQ_INCLUDES=/path/to/libzmq/include \
    ZMQ_LIBS=/path/to/libzmq/lib \
    ZMQ_H=/path/to/libzmq/include/zmq.h \
        perl Makefile.PL
    make
    make test
    make install

If you want to compile with debugging on:

    perl Makefile.PL -g

=head1 DESCRIPTION

The C<ZMQ> module is a wrapper of the 0MQ message passing library for Perl. 
It's a thin wrapper around the C API. Please read L<http://zeromq.org> for
more details on ZMQ.

=head1 CLASS WALKTHROUGH

=over 4

=item ZMQ::Raw

Use L<ZMQ::Raw> to get access to the C API such as C<zmq_init>, C<zmq_socket>, et al. Functions provided in this low level API should follow the C API exactly.

=item ZMQ::Constants

L<ZMQ::Constants> contains all of the constants that are known to be extractable from zmq.h. Do note that sometimes the list changes due to additions/deprecations in the underlying zeromq2 library. We try to do our best to make things available (at least to warn you that some symbols are deprecated), but it may not always be possible.

=item ZMQ::Context

=item ZMQ::Socket

=item ZMQ::Message

L<ZMQ::Context>, L<ZMQ::Socket>, L<ZMQ::Message> contain the high-level, more perl-ish interface to the zeromq functionalities.

=item ZMQ

Loading C<ZMQ> will make the L<ZMQ::Context>, L<ZMQ::Socket>, and 
L<ZMQ::Message> classes available as well.

=back

=head1 BASIC USAGE

To start using ZMQ, you need to create a context object, then as many ZMQ::Socket as you need:

    my $ctxt = ZMQ::Context->new;
    my $socket = $ctxt->socket( ... options );

You need to call C<bind()> or C<connect()> on the socket, depending on your usage. For example on a typical server-client model you would write on the server side:

    $socket->bind( "tcp://127.0.0.1:9999" );

and on the client side:

    $socket->connect( "tcp://127.0.0.1:9999" );

The underlying zeromq library offers TCP, multicast, in-process, and ipc connection patterns. Read the zeromq manual for more details on other ways to setup the socket.

When sendmsging data, you can either pass a ZMQ::Message object or a Perl string. 

    # the following two sendmsg() calls are equivalent
    my $msg = ZMQ::Message->new( "a simple message" );
    $socket->sendmsg( $msg );
    $socket->sendmsg( "a simple message" ); 

In most cases using ZMQ::Message is redundunt, so you will most likely use the string version.

To receive, simply call C<recvmsg()> on the socket

    my $msg = $socket->recvmsg;

The received message is an instance of ZMQ::Message object, and you can access the content held in the message via the C<data()> method:

    my $data = $msg->data;

=head1 ASYNCHRONOUS I/O WITH ZEROMQ

By default ZMQ comes with its own zmq_poll() mechanism that can handle
non-blocking sockets. You can use this by calling zmq_poll with a list of
hashrefs:

    zmq_poll([
        {
            fd => fileno(STDOUT),
            events => ZMQ_POLLOUT,
            callback => \&callback,
        },
        {
            socket => $zmq_socket,
            events => ZMQ_POLLIN,
            callback => \&callback
        },
    ], $timeout );

Unfortunately this custom polling scheme doesn't play too well with AnyEvent.

As of zeromq2-2.1.0, you can use getsockopt to retrieve the underlying file
descriptor, so use that to integrate ZMQ and AnyEvent:

    my $socket = zmq_socket( $ctxt, ZMQ_REP );
    my $fh = zmq_getsockopt( $socket, ZMQ_FD );
    my $w; $w = AE::io $fh, 0, sub {
        while ( my $msg = zmq_recvmsg( $socket, ZMQ_RCVMORE ) ) {
            # do something with $msg;
        }
        undef $w;
    };

=head1 NOTES ON MULTI-PROCESS and MULTI-THREADED USAGE

ZMQ works on both multi-process and multi-threaded use cases, but you need
to be careful bout sharing ZMQ objects.

For multi-process environments, you should not be sharing the context object.
Create separate contexts for each process, and therefore you shouldn't
be sharing the socket objects either.

For multi-thread environemnts, you can share the same context object. However
you cannot share sockets.

=head1 FUNCTIONS

=head2 version()

Returns the version of the underlying zeromq library that is being linked.
In scalar context, returns a dotted version string. In list context,
returns a 3-element list of the version numbers:

    my $version_string = ZMQ::version();
    my ($major, $minor, $patch) = ZMQ::version();

=head1 DEBUGGING XS

If you see segmentation faults, and such, you need to figure out where the error is occuring in order for the maintainers to figure out what happened. Here's a very very brief explanation of steps involved.

First, make sure to compile ZeroMQ.pm with debugging on by specifying -g:

    perl Makefile.PL -g
    make

Then fire gdb:

    gdb perl
    (gdb) R -Mblib /path/to/your/script.pl

When you see the crash, get a backtrace:

    (gdb) bt

Please put this in your bug report.

=head1 CAVEATS

This is an early release. Proceed with caution, please report
(or better yet: fix) bugs you encounter.

This module has been tested againt B<zeromq 2.1.4>. Semantics of this
module rely heavily on the underlying zeromq version. Make sure
you know which version of zeromq you're working with.

=head1 SEE ALSO

L<ZMQ::Raw>, L<ZMQ::Context>, L<ZMQ::Socket>, L<ZMQ::Message>

L<http://zeromq.org>

L<http://github.com/lestrrat/ZMQ-Perl>

=head1 AUTHOR

Daisuke Maki C<< <daisuke@endeworks.jp> >>

Steffen Mueller, C<< <smueller@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

The ZMQ module is

Copyright (C) 2010 by Daisuke Maki

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
