package Clustericious::Admin;

use strict;
use warnings;
use Clustericious::Config;
use Clustericious::Log;
use IPC::Open3 qw/open3/;
use Symbol 'gensym';
use IO::Handle;
use Term::ANSIColor;
use Hash::Merge qw/merge/;
use Mojo::Reactor;
use Data::Dumper;
use Clone qw/clone/;
use v5.10;

# ABSTRACT: Simple parallel ssh client.
our $VERSION = '0.24'; # VERSION


our @colors = qw/cyan green/;
our %waiting;
our %filtering;
our $SSHCMD = "ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o PasswordAuthentication=no";

sub _conf {
    our $conf;
    $conf ||= Clustericious::Config->new("Clad");
    return $conf;
}


sub banners {
    our $banners;
    $banners ||= _conf->banners(default => []);
    for (@$banners) {
        $_->{text} =~ s/\\n/\n/g;
        my @lines = $_->{text} =~ /^(.*)$/mg;
        $_->{lines} = \@lines;
    }
    return @$banners;
}

sub _is_builtin {
    return $_[0] =~ /^cd /;
}

sub _queue_command {
    my ($user,$w,$color,$env,$host,@command) = @_;
    TRACE "Creating ssh to $host";

    my($wtr, $ssh, $err);
    $err = gensym;
    my $ssh_cmd;
    my $login = $user ? " -l $user " : "";
    if (ref $host eq 'ARRAY') {
        $ssh_cmd = join ' ', map "$SSHCMD $login $_", @$host;
        $host = $host->[1];
    } else {
        $ssh_cmd = "$SSHCMD $login -T $host";
    }
    my $pid = open3($wtr, $ssh, $err, "trap '' HUP; $ssh_cmd /bin/sh -e") or do {
        WARN "Cannot ssh to $host: $!";
        return;
    };

    for my $cmd (@command) {
        my @cmd = $cmd;
        unless (_is_builtin($cmd)) {
            while (my ($k,$v) = each %$env) {
                unshift @cmd, "$k=$v";
            }
            unshift @cmd, qw/env/;
        }
        print $wtr "@cmd\n";
    }

    TRACE "New ssh process to $host, pid $pid";
    $waiting{$host} = $pid;

    $w->io( $ssh,
        sub {
            if (eof($ssh)) {
                TRACE "Done with $host (pid $waiting{$host}), removing handle";
                $w->remove($ssh);
                delete $waiting{$host};
                $w->stop unless keys %waiting > 0;
                return;
            }
            chomp (my $line = <$ssh>);
            print color $color if @colors;
            print "[$host] ";
            print color 'reset' if @colors;
            print "$line\n";
         });

    my $banners = [banners()];
    $w->io(
        $err,
        sub {
            state $filters = [];
            return if eof($err);
            my $skip;
            chomp (my $line = <$err>);
            for (0..$#$banners) {
                $filters->[$_] //= { line => 0 };
                my $l = \( $filters->[$_]{line} );
                my $filter_line = $banners->[$_]{lines}[$$l];
                if ($line eq $filter_line) {
                    TRACE "matched filter $_ (line $$l) : '$line'";
                    $skip = 1;
                    $$l++;
                    if ($$l >= @{ $banners->[$_]{lines} }) {
                        $filters->[$_] = undef;
                    }
                } else {
                    $filters->[$_] &&= undef;
                    TRACE "line vs filter number $_ : '$line' vs '$filter_line'";
                }
            }
            return if $skip;
            print color $color if @colors;
            print "[$host (stderr)] ";
            print color 'reset' if @colors;
            print "$line\n";
         });
    $w->watch($err,1,0);
    $w->watch($ssh,1,0);
    $w->on(error => sub {
        my ($reactor,$err) = @_;
        ERROR "$host : $err";
        delete $waiting{$host};
        $reactor->stop unless keys %waiting > 0;
    });

}


sub clusters {
    my %clusters = _conf->clusters;
    return sort keys %clusters;
}


sub aliases {
    my %aliases = _conf->aliases(default => {});
    return sort keys %aliases;
}


sub run {
    my(undef, $opts, $cluster, @cmd) = @_;
    my $dry_run = $opts->{n};
    my $user = $opts->{l};
    local @colors = @colors;
    @colors = () if $opts->{a};
    @colors = () unless -t STDOUT;
    LOGDIE "Missing cluster" unless defined $cluster;
    my $clusters = _conf->clusters(default => '') or LOGDIE "no clusters defined";
    ref($clusters) =~ /config/i or LOGDIE "clusters should be a yaml hash";
    my $hosts = $clusters->$cluster(default => '') or LOGDIE "no hosts for cluster $cluster";
    my $cluster_env = {};
    my @hosts;
    if (ref $hosts eq 'ARRAY') {
        @hosts = @$hosts;
    } else {
        @hosts = $hosts->hosts;
        if (my $proxy = $hosts->proxy(default => '')) {
            @hosts = map [ $proxy, $_ ], @hosts;
        }
        $cluster_env = $hosts->{env} || {};
    }
    LOGDIE "no hosts found" unless @hosts;
    my $alias = $_[0] or LOGDIE "No command given";

    my @command;
    if (my $command = _conf->aliases(default => {})->{$alias}) {
        DEBUG "Found alias $alias";
        @command = ref $command ? @$command : ( $command );
    } else {
        DEBUG "No alias $alias using @cmd";
        @command = @cmd;
    }
    LOGDIE "No command" unless @command && $command[0];
    s/\$CLUSTER/$cluster/ for @command;
    DEBUG "Running @command on cluster $cluster";
    my $i = 0;
    my $env = _conf->{env} || {};
    $env = merge( $cluster_env, $env );
    TRACE "Env : ".Dumper($env);
    my $watcher = Mojo::Reactor->detect->new;
    for my $host (@hosts) {
        $i++;
        $i = 0 if $i == @colors;
        my $where = ( ref $host eq 'ARRAY' ? $host->[-1] : $host );
        if ($dry_run) {
            INFO "Not running on $where : " . join '; ', @command;
        } else {
            TRACE "Running on $where : " . join ';', @command;
            _queue_command( $user, $watcher, $colors[$i], $env, $host, @command );
        }
        if ( Log::Log4perl::get_logger()->is_trace ) {
            $watcher->recurring(
                2 => sub {
                    TRACE "Waiting for $host (pid $waiting{$host})" if $waiting{$host};
                    TRACE "Not waiting for any host" unless keys %waiting;
                }
            );
        }
    }
    $watcher->recurring(1 => sub { TRACE "tick" } );
    $watcher->start unless $dry_run;
    
    0;
}

1;


__END__
=pod

=head1 NAME

Clustericious::Admin - Simple parallel ssh client.

=head1 VERSION

version 0.24

=head1 DESCRIPTION

This is a simple parallel ssh client, with a verbose
configuration syntax for running ssh commands on various
clusters of machines.

Most of the documentation is in the command line tool L<clad>.

=head1 FUNCTIONS

=head2 banners

 my $banners = Clustericious::Admin->banners;

return the banners from the configuration file as a list.

=head2 clusters

 my @clusters = Clustericious::Admin->clusters;

Return the list of clusters in the configuration file

=head2 aliases

 my @aliases = Clustericious::Admin->aliases;

Return the list of aliases from the configuration file

=head2 run

 Clustericious::Admin->run(\%options, $cluster, $command);

Run the given command on all the hosts in the given cluster.
Returns the exit value for the equivalent clad command, which
is currently always 0, but in the future might be non-zero
for failure.  Options include:

=over 4

=item n

Set to true for a dry run

=item l

Set to the username that you want to connect to if not using the default.

=item a

Set to true to turn off color

=back

=head1 SEE ALSO

L<clad>

=head1 TODO

Handle escaping of quote/meta characters better.

=head1 AUTHOR

original author: Brian Duggan

current maintainer: Graham Ollis <plicease@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by NASA GSFC.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

