package ZMQ::Raw;
use strict;
use XSLoader;

BEGIN {
    our $VERSION = '1.00_01';

    our @ISA = qw(Exporter);
    # XXX it's a hassle, but keep it in sync with ZMQ.pm
    # by loading this here, we can make ZMQ::Raw independent
    # of ZMQ while keeping the dist name as ZMQ
    XSLoader::load('ZMQ', $VERSION);
}

our @EXPORT = qw(
    zmq_init
    zmq_term

    zmq_msg_close
    zmq_msg_data
    zmq_msg_init
    zmq_msg_init_data
    zmq_msg_init_size
    zmq_msg_size
    zmq_msg_copy
    zmq_msg_move

    zmq_bind
    zmq_close
    zmq_connect
    zmq_getsockopt
    zmq_recv
    zmq_recvmsg
    zmq_send
    zmq_sendmsg
    zmq_setsockopt
    zmq_socket

    zmq_poll

    zmq_device
);

1;

__END__

=head1 NAME

ZMQ::Raw - Low-level API for ZMQ

=head1 FUNCTIONS

=head2 zmq_init

=head2 zmq_term

=head2 zmq_msg_close

=head2 zmq_msg_data

=head2 zmq_msg_init

=head2 zmq_msg_init_data

=head2 zmq_msg_init_size

=head2 zmq_msg_size

=head2 zmq_msg_move

=head2 zmq_msg_copy

=head2 zmq_bind

=head2 zmq_close

=head2 zmq_connect

=head2 zmq_getsockopt

=head2 zmq_recvmsg

=head2 zmq_send

    $bytes_written = zmq_send( $buffer, $size, $flags )

If C<$size> is set to -1, then the length is automatically calculated from $buffer. Default value is -1, but be careful, if you pass 0, then it's not the same as passing undef

    # automatically calculate
    zmq_send( $buf, undef, $flags );
    
    # write 0 bytes!
    zmq_send( $buf, 0, $flags );

=head2 zmq_send_as

=head2 zmq_sendmsg( $msg_object )

=head2 zmq_setsockopt

=head2 zmq_socket

=head2 zmq_poll( \@list_of_hashrefs, $timeout )

Calls zmq_poll on the given items as specified by @list_of_hashrefs.
Each element in @list_of_hashrefs should be a hashref containing the following keys:

=over 4

=item socket

Contains the ZMQ::Raw::Socket object to poll.

=item fd

Contains the file descriptor to poll. Either one of socket or fd must be specified. If both are specified, 'socket' will take precedence.

=item events

A bitmask of ZMQ_POLLIN, ZMQ_POLLOUT, ZMQ_POLLERR

=item callback

Callback that gets invoked. Takes no arguments.

=back

=head2 zmq_device( device, insocket, outsocket )

=cut
