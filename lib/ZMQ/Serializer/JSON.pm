package ZMQ::Serializer::JSON;
use ZMQ;
use ZMQ::Serializer;
use JSON '2.00';

ZMQ::Serializer::register_read_type(json => \&JSON::decode_json);
ZMQ::Serializer::register_write_type(json => \&JSON::encode_json);

1;

__END__

=head1 NAME

ZMQ::Serializer::JSON - JSON Serializer For ZMQ.pm

=head1 SYNOPSIS

    use ZMQ;
    use ZMQ::Serializer::JSON;

    my $ctxt   = ZMQ::Context->new;
    my $socket = $ctxt->socket( ... );

    $socket->sendmsg_as( json => \%hash );
    $socket->sendmsg_as( json => \@list );

    # ... on the other side ...

    my $hash = $socket->recvmsg_as( 'json' );
    my $list = $socket->recvmsg_as( 'json' );

=head1 CUSTOMIZING

If you want to tweak the serializer option, do something like this:

    my $coder = JSON->new->utf8->pretty; # pretty print
    ZMQ::register_write_type( json_pretty => sub { $coder->encode($_[0]) } );
    ZMQ::register_read_type( json_pretty => sub { $coder->decode($_[0]) } );

Note that this will have a GLOBAL effect. If somebody else tries to register
'json_pretty', then this setting will be overwritten

=cut
