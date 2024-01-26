class Concurrent::Iterator does Iterator {
    has Mu $!target-iterator;
    has $!lock;
    has $!exception;

    method new(Iterable:D $target) {
        self.bless(:$target)
    }

    submethod TWEAK(:$target --> Nil) {
        $!target-iterator := $target.iterator;
        $!lock := Lock.new;
    }

    method pull-one() {
        $!lock.protect: {
            if $!target-iterator {
                my \pulled = $!target-iterator.pull-one;
                CATCH { $!exception := $_; $!target-iterator := Mu }
                $!target-iterator := Mu if pulled =:= IterationEnd;
                pulled
            }
            elsif $!exception {
                $!exception.rethrow
            }
            else {
                IterationEnd
            }
        }
    }
}

proto concurrent-iterator($) is export {*}
multi concurrent-iterator(Iterable:D \iterable) {
    Concurrent::Iterator.new(iterable)
}
multi concurrent-iterator($other) {
    concurrent-iterator($other.list)
}

sub concurrent-seq($target) is export {
    Seq.new(concurrent-iterator($target))
}

=begin pod

=head1 NAME

Concurrent::Iterator - Enables safe concurrent consumption of Iterable values

=head1 SYNOPSIS

=begin code :lang<raku>

use Concurrent::Iterator;

=end code

=head1 DESCRIPTION

A standard Raku C<Iterator> should only be consumed from one thread at
a time.  C<Concurrent::Iterator> allows any C<Iterable> to be iterated
concurrently.

-head1 SYNOPSIS

=begin code :lang<raku>

use Concurrent::Iterator;

# Make a concurrent iterator over an infinite Range
# of ascending integers.
my $ids = concurrent-iterator(0..Inf);

# Many concurrent workers can use it to obtain the IDs, being
# confident of no duplication.
do await for ^10 {
    start {
        say "I got $ids.pull-one()";
    }
}

=end code

=head1 Overview

The purpose of C<Concurrent::Iterator> is to allow multiple threads
to safely race to obtain values from a single iterable source of data.
It:

=item Uses locking to ensure that only one thread can be pulling a
 value from the underlying iterator at a time

=item Will return C<IterationEnd> to all future requests for values
after it is returned by the underlying iterator (it is erroneous to
call pull-one on a normal Iterator that has already produced
C<IterationEnd>)

=item Will rethrow any exception thrown by the underlying iterator
on all future requests

Together, these mean that it is possible to use a
C<Concurrent::Iterator> to have many workers compete for data items
to process, and have them all terminate on end of sequence or
exception. That might look something like this

=begin code :lang<raku>

my \to-process = concurrent-seq(@data);
my @results = flat await do for ^4 {
    start (compute-stuff($_) for to-process)
}

=end code

However, there's no reason to use C<Concurrent:Iterator> for such
a simple use case. It is far more simply expressed without this
module as just:

=begin code :lang<raku>

my @results = @data.hyper.map(&compute-stuff);

=end code

Or, if you really wanted to enforce one-at-a-time and exactly 4
workers:

=begin code :lang<raku>

my @results = @data.hyper(:degree(4), :batch(1)).map(&compute-stuff);

=end code

=head1 Concurrent::Iterator

The C<Concurrent::Iterator> class is constructed with a single
positional argument, which must be of type C<Iterable:D>:

=begin code :lang<raku>

my $ci = Concurrent::Iterator.new(1..Inf);

=end code

It implements the Raku standard C<Iterator> interface.

=head1 Convenience subs

There is a convenience sub to form a C<Concurrent::Iterator>:

=begin code :lang<raku>

my $ci = concurrent-iterator(1..Inf);

=end code

There is also one to have it wrapped in a C<Seq>:

=begin code :lang<raku>

my $cs = concurrent-seq(1..Inf);

=end code

Which literally just passes the result of calling
C<concurrent-iteratorr> to C<Seq.new>.

=head1 AUTHOR

Jonathan Worthington

=head1 COPYRIGHT AND LICENSE

Copyright 2016 - 2024 Jonathan Worthington

Copyright 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
