package App::Base::Script::OnlyOne;
use Moose::Role;
use Path::Class;
use File::Flock::Tiny;

=head1 NAME

App::Base::Script::OnlyOne

=head1 SYNOPSIS

    use Moose;
    extends 'App::Base::Script';
    with 'App::Base::Script::OnlyOne';

=head1 DESCRIPTION

With this role your script will refuse to start if another copy of the script
is running already (or if it is deadlocked or entered an infinite loop because
of programming error).

=cut

around script_run => sub {
    my $orig = shift;
    my $self = shift;

    my $class   = ref $self;
    my $piddir  = $ENV{APP_BASE_DAEMON_PIDDIR} || Path::Class::Dir->new('', 'var', 'run');
    my $pidfile = Path::Class::File->new($piddir, "$class.pid");
    my $lock    = File::Flock::Tiny->write_pid($pidfile);
    die "Couldn't lock pid file, probably $class is already running" unless $lock;

    return $self->$orig(@_);
};

1;
