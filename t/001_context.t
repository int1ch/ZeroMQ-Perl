use strict;
use Test::More;
use Test::Fatal;
BEGIN {
    use_ok "ZeroMQ::Raw", qw(
        zmq_init
        zmq_term
    );
}

subtest 'sane creation/destroy' => sub {
    is exception {
        my $context = zmq_init(5);
        isa_ok $context, "ZeroMQ::Raw::Context";
        zmq_term( $context );
    }, undef, "sane allocation / cleanup for context";

    is exception {
        my $context = zmq_init();
        zmq_term( $context );
        zmq_term( $context );
    }, undef, "double zmq_term should not die";
};

done_testing;