package App::Base::Daemon::Supervisor;

=head1 NAME

App::Base::Daemon::Supervisor

=head1 SYNOPSIS

    package App::Base::Daemon::Foo;
    use Moose;
    with 'App::Base::Daemon::Supervisor';

    sub documentation { return 'foo'; }
    sub options { ... }
    sub supervised_process {
        # the main daemon process
        while(1) {
            # check if supervisor is alive, exit otherwise
            $self->ping_supervisor;
            # do something
            ...
        }
    }
    sub supervised_shutdown {
        # this is called during shutdown
    }

=head1 DESCRIPTION

App::Base::Daemon::Supervisor allows to run code under supervision. It forks child
process and restarts it if it exits. It also supports zero downtime reloading.

=cut

use 5.010;
use Moose::Role;
with 'App::Base::Daemon';

use namespace::autoclean;
use Socket qw();
use POSIX qw(:errno_h);
use Time::HiRes;
use IO::Handle;
use Try::Tiny;

=head1 REQUIRED METHODS

Class consuming this role must implement following methods:

=cut

=head2 supervised_process

The main daemon subroutine. Inside this subroutine you should periodically
check that supervisor is still alive. If supervisor exited, daemon should also
exit.

=cut

requires 'supervised_process';

=head2 supervised_shutdown

This subroutine is executed then daemon process is shutting down. Put cleanup
code inside.

=cut

requires 'supervised_shutdown';

=head1 ATTRIBUTES

=cut

=head2 is_supervisor

returns true inside supervisor process and false inside supervised daemon

=cut

has is_supervisor => (
    is      => 'rw',
    default => 1,
);

=head2 delay_before_respawn

how long supervisor should wait after child process exited before starting a
new child. Default value is 5.

=cut

has delay_before_respawn => (
    is      => 'rw',
    default => 5,
);

has supervisor_pipe => (
    is     => 'rw',
    writer => '_supervisor_pipe',
);
has _child_pid => (is => 'rw');

=head1 METHODS

=cut

=head2 $self->ping_supervisor

Should only be called from supervised process. Checks if supervisor is alive
and initiates shutdown if it is not.

=cut

sub ping_supervisor {
    my $self = shift;
    my $pipe = $self->supervisor_pipe or $self->error("Supervisor pipe is not defined");
    say $pipe "ping";
    my $pong = <$pipe>;
    unless (defined $pong) {
        $self->error("Error reading from supervisor pipe: $!");
    }
    return;
}

=head2 $self->ready_to_take_over

Used to support host restart. If daemon support hot restart,
I<supervised_process> is called while the old daemon is still running.
I<supervised_process> should perform initialization, e.g. open listening
sockets, and then call this method. Method will cause termination of old daemon
and after return the new process may start serving clients.

=cut

sub ready_to_take_over {
    my $self = shift;
    my $pipe = $self->supervisor_pipe or confess "Supervisor pipe is not defined";
    say $pipe "takeover";
    my $ok = <$pipe>;
    defined($ok) or $self->error("Failed to take over");
    return;
}

=head2 $self->daemon_run

See L<App::Base::Daemon>

=cut

sub daemon_run {
    my $self = shift;
    $self->_set_hot_reload_handler;

    while (1) {
        socketpair my $chld, my $par, Socket::AF_UNIX, Socket::SOCK_STREAM, Socket::PF_UNSPEC;
        my $pid = fork;
        $self->_child_pid($pid);
        if ($pid) {
            local $SIG{QUIT} = sub {
                kill TERM => $pid;
                waitpid $pid, 0;
                exit 0;
            };
            $self->debug("Forked a supervised process $pid");
            $chld->close;
            $par->autoflush(1);
            $self->_supervisor_pipe($par);
            while (<$par>) {
                chomp;
                if ($_ eq 'ping') {
                    say $par 'pong';
                } elsif ($_ eq 'takeover') {
                    $self->_control_takeover;
                    say $par 'ok';
                } elsif ($_ eq 'shutdown') {
                    $self->debug("Worker asked for shutdown");
                    kill KILL => $pid;
                    close $par;
                } else {
                    $self->warning("Received unknown command from the supervised process: $_");
                }
            }
            $self->debug("Child closed control connection");
            my $kid = waitpid $pid, 0;
            $self->warning("Supervised process $kid exited with status $?");
        } elsif (not defined $pid) {
            $self->warning("Couldn't fork: $!");
        } else {
            local $SIG{USR2};
            $par->close;
            $chld->autoflush(1);
            $self->_supervisor_pipe($chld);
            $self->is_supervisor(0);
            $self->supervised_process;
            exit 0;
        }
        Time::HiRes::usleep(1_000_000 * $self->delay_before_respawn);
    }

    # for critic
    return;
}

# this initializes SIGUSR2 handler to perform hot reload
sub _set_hot_reload_handler {
    my $self = shift;

    return unless $self->can_do_hot_reload;
    my $upgrading;

    ## no critic (RequireLocalizedPunctuationVars)
    $SIG{USR2} = sub {
        return unless $ENV{APP_BASE_DAEMON_PID} == $$;
        if ($upgrading) {
            $self->warning("Received USR2, but hot reload is already in progress");
            return;
        }
        $self->warning("Received USR2, initiating hot reload");
        my $pid;
        unless (defined($pid = fork)) {
            $self->warning("Could not fork, cancelling reload");
        }
        unless ($pid) {
            exec($ENV{APP_BASE_SCRIPT_EXE}, @{$self->{orig_args}}) or $self->error("Couldn't exec: $!");
        }
        $upgrading = time;
        if ($SIG{ALRM}) {
            $self->warning("ALRM handler is already defined!");
        }
        $SIG{ALRM} = sub {
            $self->warning("Hot reloading timed out, cancelling");
            kill KILL => $pid;
            undef $upgrading;
        };
        alarm 60;
    };
    {
        my $usr2 = POSIX::SigSet->new(POSIX::SIGUSR2());
        my $old  = POSIX::SigSet->new();
        POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), $usr2, $old);
    }
    $self->debug("Set handler for USR2");

    return;
}

my $pid;

# kill the old daemon and lock pid file
sub _control_takeover {
    my $self = shift;

    ## no critic (RequireLocalizedPunctuationVars)

    # if it is first generation, when pid file should be already locked in App::Base::Daemon
    if ($ENV{APP_BASE_DAEMON_GEN} > 1 and $ENV{APP_BASE_DAEMON_PID} != $$) {
        kill QUIT => $ENV{APP_BASE_DAEMON_PID};
        if ($self->getOption('no-pid-file')) {
            # we don't have pid file, so let's just poke it to death
            my $attempts = 14;
            while (kill(($attempts == 1 ? 'KILL' : 'ZERO') => $ENV{APP_BASE_DAEMON_PID}) and $attempts--) {
                Time::HiRes::usleep(500_000);
            }
        } else {
            local $SIG{ALRM} = sub { $self->warn("Couldn't lock the file. Sending KILL to previous generation process"); };
            alarm 5;
            # We may fail because two reasons:
            # a) previous process didn't exit and still holds the lock
            # b) new process was started and locked pid
            $pid = try { File::Flock::Tiny->lock($self->pid_file) };
            unless ($pid) {
                # So let's try killing old process, if after that locking still will fail
                # then probably it is the case b) and we should exit
                kill KILL => $ENV{APP_BASE_DAEMON_PID};
                $SIG{ALRM} = sub { $self->error("Still couldn't lock pid file, aborting") };
                alarm 5;
                $pid = File::Flock::Tiny->lock($self->pid_file);
            }
            alarm 0;
            $pid->write_pid;
        }
        $self->info("Process $$, is generation $ENV{APP_BASE_DAEMON_GEN} of " . ref $self);
    }
    $ENV{APP_BASE_DAEMON_PID} = $$;
    return;
}

=head2 $self->handle_shutdown

See L<App::Base::Daemon>

=cut

sub handle_shutdown {
    my $self = shift;
    if ($self->is_supervisor) {
        kill TERM => $self->_child_pid if $self->_child_pid;
    } else {
        $self->supervised_shutdown;
    }

    return;
}

sub DEMOLISH {
    my $self = shift;
    shutdown $self->supervisor_pipe, 2 if $self->supervisor_pipe;
    return;
}

1;
