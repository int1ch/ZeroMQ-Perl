package ZMQ::Context;
use strict;
use ZMQ::Raw ();

sub new {
    my ($class, $nthreads) = @_;
    if (! defined $nthreads || $nthreads <= 0) {
        $nthreads = 1;
    }

    bless {
        _ctxt => ZMQ::Raw::zmq_init($nthreads),
    }, $class;
}

sub ctxt {
    $_[0]->{_ctxt};
}

sub socket {
    return ZMQ::Socket->new(@_); # $_[0] should contain the context
}

sub term {
    my $self = shift;
    ZMQ::Raw::zmq_term($self->ctxt);
}

1;

__END__

=head1 NAME

ZMQ::Context - A 0MQ Context object

=head1 SYNOPSIS

  use ZMQ qw/:all/;
  
  my $cxt = ZMQ::Context->new;
  my $sock = ZMQ::Socket->new($cxt, ZMQ_REP);

=head1 DESCRIPTION

Before opening any 0MQ Sockets, the caller must initialise
a 0MQ context.

=head1 METHODS

=head2 new($nthreads)

Creates a new C<ZMQ::Context>.

Optional arguments: The number of io threads to use. Defaults to 1.

=head2 term()

Terminates the current context. You *RARELY* need to call this yourself,
so don't do it unless you know what you're doing.

=head2 socket($type)

Short hand for ZMQ::Socket::new. 

=head2 ctxt

Return the underlying ZMQ::Raw::Context object

=head1 CAVEATS

While in principle, C<ZMQ::Context> objects are thread-safe,
they are currently not cloned when a new Perl ithread is spawned.
The variables in the new thread that contained the context in
the parent thread will be a scalar reference to C<undef>
in the new thread. This could be fixed with better control
over the destructor calls.

=head1 SEE ALSO

L<ZMQ>, L<ZMQ::Socket>

L<http://zeromq.org>

L<ExtUtils::XSpp>, L<Module::Build::WithXSpp>

=head1 AUTHOR

Daisuke Maki E<lt>daisuke@endeworks.jpE<gt>

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

The ZMQ module is

Copyright (C) 2010 by Daisuke Maki

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
