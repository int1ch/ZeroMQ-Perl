package ZMQ::Serializer;
use strict;
use ZMQ;
use ZMQ::Socket;

our %SERIALIZERS;
our %DESERIALIZERS;
sub _get_serializer { $SERIALIZERS{$_[1]} }
sub _get_deserializer { $DESERIALIZERS{$_[1]} }
sub register_read_type { $DESERIALIZERS{$_[0]} = $_[1] }
sub register_write_type { $SERIALIZERS{$_[0]} = $_[1] }

sub ZMQ::Socket::recvmsg_as {
    my ($self, $type, $flags) = @_;

    my $deserializer = ZMQ::Serializer->_get_deserializer( $type );
    if (! $deserializer ) {
        Carp::croak("No deserializer $type found");
    }

    # XXX Must return in order to accomodate for DONTBLOCK
    my $msg = $self->recvmsg( $flags, $flags ) or return;
    $deserializer->( $msg->data );
}

sub ZMQ::Socket::send_as {
    my ($self, $type, $data, $flags) = @_;

    my $serializer = ZMQ::Serializer->_get_serializer( $type );
    if (! $serializer ) {
        Carp::croak("No serializer $type found");
    }

    $self->send( $serializer->( $data ), $flags );
}

1;

__END__

=head1 NAME

ZMQ::Serializer - Enable Serializers

=head1 SYNOPSIS

    use ZMQ qw(:all);
    use ZMQ::Serializer;

    my $ctxt = ZMQ::Context->new;
    my $socket = $ctxt->socket( ZMQ_REQ );

    $socket->send_as( json => { foo => 1 } );
    my $hash = $socket->recv_as( 'json' );

=head1 DESCRIPTION

You can add a simple serialization/deserialization mechanism to ZMQ by enabling this module.

To enable serialization, you must load ZMQ::Serializer:

    use ZMQ;
    use ZMQ::Serializer;

This will add C<ZMQ::Socket::sendmsg_as()> and C<ZMQ::Socket::recvmsg_as> methods.

You also need to tell it how/what to serialize/deserialize.
To do this, use C<register_write_type()> to register a name and an
associated callback to serialize the data. For example, for JSON we do
the following (this is already done for you in ZMQ.pm if you have
JSON.pm installed):

    use JSON ();
    ZMQ::Serializer::register_write_type('json' => \&JSON::encode_json);
    ZMQ::Serializer::register_read_type('json' => \&JSON::decode_json);

Then you can use C<sendmsg_as()> and C<recvmsg_as()> to specify the serialization 
type as the first argument:

    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket( ZMQ_REQ );

    $sock->sendmsg_as( json => $complex_perl_data_structure );

The otherside will receive a JSON encoded data. The receivind side
can be written as:

    my $ctxt = ZMQ::Context->new();
    my $sock = $ctxt->socket( ZMQ_REP );

    my $complex_perl_data_structure = $sock->recvmsg_as( 'json' );

No serializers are loaded by default. Look for ZMQ::Serializer::*
namespace in CPAN.

=head1 FUNCTIONS

=head2 register_read_type($name, \&callback)

Register a read callback for a given C<$name>. This is used in C<recvmsg_as()>.
The callback receives the data received from the socket.

=head2 register_write_type($name, \&callback)

Register a write callback for a given C<$name>. This is used in C<sendmsg_as()>
The callback receives the Perl structure given to C<sendmsg_as()>

=head1 SEE ALSO

L<ZMQ::Serializer::JSON>

=cut