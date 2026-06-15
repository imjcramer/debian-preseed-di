package Zram::Writeback::Lock;

use strict;
use warnings;
use Fcntl qw(:flock);
use Zram::Writeback::Util qw(ensure_dir);

sub new {
    my ($class, %arg) = @_;
    my $path = $arg{path} or die 'lock path is required';
    return bless { path => $path, fh => undef }, $class;
}

sub acquire {
    my ($self, %opt) = @_;
    my $dir = $self->{path};
    $dir =~ s{/[^/]+\z}{};
    ensure_dir($dir, 0755) if $dir ne '' && !-d $dir;
    open my $fh, '>>', $self->{path} or die "open($self->{path}): $!";
    my $flags = $opt{nonblock} ? LOCK_EX | LOCK_NB : LOCK_EX;
    flock($fh, $flags) or die "flock($self->{path}): $!";
    $self->{fh} = $fh;
    return $self;
}

sub release {
    my ($self) = @_;
    return 1 unless $self->{fh};
    flock($self->{fh}, LOCK_UN);
    close $self->{fh};
    $self->{fh} = undef;
    return 1;
}

sub DESTROY {
    my ($self) = @_;
    $self->release if $self && $self->{fh};
}

1;
