package App::Base::Script::Common;
use Moose::Role;

=head1 NAME

App::Base::Script::Common - Behaviors that are common to App::Base::Script and App::Base::Daemon

=head1 DESCRIPTION

App::Base::Script::Common provides infrastructure that to the App::Base::Script and 
App::Base::Daemon classes, including:

- Standardized option parsing
- Standardized logging

=cut

## no critic (RequireArgUnpacking)

use App::Base::Script::Option;
use Log::Log4perl;

use Cwd qw( abs_path );
use Carp qw( croak );
use File::Basename qw( basename );
use Getopt::Long;
use IO::Handle;
use List::Util qw( max );
use POSIX qw( strftime );
use Text::Reform qw( form break_wrap );
use Try::Tiny;

use MooseX::Types -declare => [qw(bom_syslog_facility)];
use MooseX::Types::Moose qw( Str Bool );

has 'has_tty' => (
    is      => 'rw',
    isa     => Bool,
    default => sub {
        my $tty_exit_status = system("tty --silent") / 256;    # info tty for more info
        $tty_exit_status ? 0 : 1;
    },
);

has 'return_value' => (
    is      => 'rw',
    default => 0
);

=head1 REQUIRED SUBCLASS METHODS

=head2 documentation

Returns a scalar (string) containing the documentation portion
of the script's usage statement.

=cut

requires 'documentation';    # Seriously, it does.

# For our own subclasses like App::Base::Script and App::Base::Daemon

=head2 __run

For INTERNAL USE ONLY: Used by subclasses such as App::Base::Script and
App::Base::Daemon to redefine dispatch rules to their own required
subclass methods such as script_run() and daemon_run().

=cut

requires '__run';

=head2 error

All App::Base::Script::Common-implementing classes must have an
error() method that handles exceptional cases which also 
require a shutdown of the running script/daemon/whatever.

=cut

requires 'error';

=head1 OPTIONAL SUBCLASS METHODS

=head2 options

Concrete subclasses can specify their own options list by defining
a method called options() which returns an arrayref of
App::Base::Script::Option objects. Alternatively, your script/daemon
can simply get by with the standard --help/quiet/verbose/whatever
options provided by its role.

=cut

sub options {
    my $self = shift;
    return [];
}

=head1 ATTRIBUTES

=head2 _option_values

The (parsed) option values, including defaults values if none were
specified, for all of the options declared by $self. This accessor
should not be called directly; use getOption() instead.

=cut

has '_option_values' => (
    is  => 'rw',
    isa => 'HashRef',
);

=head2 orig_args

An arrayref of arguments as they existed prior to option parsing.

=cut

has 'orig_args' => (
    is  => 'rw',
    isa => 'ArrayRef[Str]',
);

=head2 parsed_args

An arrayref of the arguments which remained after option parsing.

=cut

has 'parsed_args' => (
    is  => 'rw',
    isa => 'ArrayRef[Str]',
);

=head2 script_name

The name of the running script, computed from $0 and used for logging.

=cut

has 'script_name' => (
    is      => 'ro',
    default => sub { File::Basename::basename($0); },
);

=head2 _do_console_logging

For internal use only. Determines whether to log messages to the console
when syslog-only logging would normally be the correct behavior.

=cut

has '_do_console_logging' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
);

has logger => (
    is      => 'ro',
    lazy    => 1,
    builder => 'build_logger'
);

sub build_logger {
    return Log::Log4perl::get_logger;
}

=head1 METHODS

=head2 BUILDARGS

Combines the results of base_options() and options() and then parses the
command-line arguments of the script. Exits with a readable error message
if the script was invoked in a non-sensical or invalid manner.

=cut

sub BUILDARGS {
    my $class   = shift;
    my $arg_ref = shift;

    ## no critic (RequireLocalizedPunctuationVars)
    $ENV{APP_BASE_SCRIPT_EXE} = abs_path($0);
    $arg_ref->{orig_args} = [@ARGV];

    my $results = $class->_parse_arguments(\@ARGV);
    if ($results->{parse_result}) {
        $arg_ref->{_option_values} = $results->{option_values};
        $arg_ref->{parsed_args}    = $results->{parsed_args};
        # This exits.
        $class->usage(0) if ($results->{option_values}->{'help'});
    } else {
        # This exits.
        $class->usage(1);
    }

    return $arg_ref;
}

=head2 all_options

Returns the composition of options() and base_options().

=cut

sub all_options {
    my $self = shift;
    return [@{$self->options}, @{$self->base_options}];
}

=head2 base_options

The options provided for every classes which implements App::Base::Script::Common.
See BUILT-IN OPTIONS

=cut

sub base_options {
    return [
        App::Base::Script::Option->new(
            name          => 'help',
            documentation => 'Show this help information',
        ),
        App::Base::Script::Option->new(
            name          => 'quiet',
            documentation => 'Do not print debugging or informational messages',
        ),
        App::Base::Script::Option->new(
            name          => 'verbose',
            documentation => 'Be very verbose with information and debugging messages',
        ),
    ];
}

=head2 switch_name_width

Computes the maximum width of any of the switch (option) names.

=cut

sub switch_name_width {
    my $self = shift;
    return max(map { length($_->display_name) } @{$self->all_options});
}

=head2 switches

Generates the switch table output of the usage statement.

=cut

sub switches {
    my $self = shift;

    my $col_width = $ENV{COLUMNS} || 76;

    my $max_option_length = $self->switch_name_width;
    my $sw                = '[' x ($max_option_length + 2);
    my $doc               = '[' x ($col_width - $max_option_length - 1);

    my @lines = map {
        form { break => break_wrap }, "$sw $doc", '--' . $_->display_name, $_->show_documentation;
      } (
        sort {
            $a->name cmp $b->name
          } (@{$self->all_options}));

    return join('', @lines);
}

=head2 cli_template

The template usage form that should be shown to the user in the usage
statement when --help or an invalid invocation is provided.

Defaults to "(program name) [options]", which is pretty standard Unix.

=cut

sub cli_template {
    return "$0 [options] ";    # Override this if your script has a more complex command-line
                               # invocation template such as "$0[options] company_id [list1 [, list2 [, ...]]] "
}

=head2 usage

Outputs a statement explaining the usage of the script, then exits.

=cut

sub usage {
    my $self      = shift;
    my $log_error = shift;

    my $col_width = $ENV{COLUMNS} || 76;

    my $format = '[' x $col_width;

    my $message = join('', "\n", form({break => break_wrap}, $format, ["Usage: " . $self->cli_template, split(/[\r\n]/, $self->documentation)]));

    $message .= "\nOptions:\n\n";

    $message .= $self->switches . "\n\n";

    print STDERR $message;

    return $log_error ? $self->error($message) : (exit 1);

}

=head2 getOption

Returns the value of a specified option. For example, getOption('help') returns
1 or 0 depending on whether the --help option was specified. For option types
which are non-boolean (see App::Base::Script::Option) the return value is the actual
string/integer/float provided on the common line - or undef if none was provided.

=cut

sub getOption {
    my $self   = shift;
    my $option = shift;

    if (exists($self->_option_values->{$option})) {
        return $self->_option_values->{$option};
    } else {
        croak "Unknown option $option";
    }

}

=head2 run

Runs the script, returning the return value of __run

=cut

sub run {
    my $self      = shift;
    my $log_level = 'WARN';
    $log_level = 'ERROR' if $self->getOption("quiet");
    $log_level = 'DEBUG' if $self->getOption("verbose");

    # For smooth output of console-logged messages
    STDERR->autoflush(1) if ($self->has_tty);
    BOM::Utility::Log4perl::set_console_config($log_level)
      if $self->_do_console_logging;

    # This is implemented by subclasses of App::Base::Script::Common
    $self->__run;
    return $self->return_value;
}

=head2 _parse_arguments

Parses the arguments in @ARGV, returning a hashref containing:

- The parsed arguments (that is, those that should remain in @ARGV)
- The option values, as a hashref, including default values
- Whether the parsing encountered any errors

=cut

sub _parse_arguments {
    my $self = shift;
    my $args = shift;

    local @ARGV = (@$args);

    # Build the hash of options to pass to Getopt::Long
    my $options      = [@{$self->base_options}, @{$self->options}];
    my %options_hash = ();
    my %getopt_args  = ();

    foreach my $option (@$options) {
        my $id   = $option->name;
        my $type = $option->option_type;
        if ($type eq 'string') {
            $id .= '=s';
        } elsif ($type eq 'integer') {
            $id .= '=i';
        } elsif ($type eq 'float') {
            $id .= '=f';
        }

        my $scalar = $option->default;
        $getopt_args{$option->name} = \$scalar;
        $options_hash{$id} = \$scalar;
    }

    my $result = GetOptions(%options_hash);
    my %option_values = map { $_ => ${$getopt_args{$_}} } (keys %getopt_args);
    return {
        parse_result  => $result,
        option_values => \%option_values,
        parsed_args   => \@ARGV
    };

}

=head2 debug

Formats its arguments and outputs them to STDOUT and/or syslog at logging level DEBUG.

=cut

sub debug {
    my $self = shift;
    return $self->logger->debug(join " ", @_);
}

=head2 info

Formats its arguments and outputs them to STDOUT and/or syslog at logging level INFO.

=cut

sub info {
    my $self = shift;
    return $self->logger->info(join " ", @_);
}

=head2 notice

Formats its arguments and outputs them to STDOUT and/or syslog at logging level NOTICE.

=cut

sub notice {
    my $self = shift;
    return $self->info(@_);
}

=head2 warning

Formats its arguments and outputs them to STDOUT and/or syslog at logging level WARN.

=cut

sub warning {
    my $self = shift;
    return $self->logger->warn(join " ", @_);
}

## no critic
sub warn {
    my $self = shift;
    $self->warning(@_);
}

=head2 __error

Dispatches its arguments to the subclass-provided error() method (see REQUIRED
SUBCLASS METHODS), then exits.

=cut

sub __error {
    my $self = shift;
    $self->logger->error(join " ", @_);
    exit(-1);
}

1;

__END__

=head1 USAGE

Invocation of a App::Base::Script::Common-based program is accomplished as follows:

- Define a class that derives (via 'use Moose' and 'with') from App::Base::Script::Common

- Instantiate an object of that class via new( )

- Run the program by calling run( ). The return value of run( ) is the exit
status of the script, and should typically be passed back to the calling
program via exit()

=head2 The new() method

A Moose-style constructor for the App::Base::Script::Common-derived class.
Every such class has one important attribute:

- options: an array ref of App::Base::Script::Option objects to be added to the
command-line processing for the script. See App::Base::Script::Option for
more information.

=head2 Logging methods

- debug( @message ) - If --verbose is specified, prints a log line containing
@message to STDERR

- info( @message ) - If --quiet is not specified, prints a log line containing
@message to STDERR. NOTE: If the script is running without a controlling tty
(e.g., in a crontab), info() messages WILL NOT be printed to STDERR unless
--opt-verbose is specified. However, while connected to a tty, info() messages
will be printed to STDERR.

- notice( @message ) - If --quiet is not specified, prints a log line containing
@message to STDERR

- warning( @message ) - Prints a log line containing @message to STDERR.

- error( @message ) - Depends on the subclass' (or role's) implementation
of error(), but usually it results in the program terminating and appropriate
messages being logged somewhere.

=head2 Options handling

One of the most useful parts of App::Base::Script::Common is the simplified access to
options processing. The getOption() method allows your script to determine the
value of a given option, determined as follows:

1) If given as a command line option (registered via options hashref)
2) The default value specified in the App::Base::Script::Option object that
was passed to the options() attribute at construction time.

For example, if your script registers an option 'foo' by saying

  my $object = MyScript->new( options => [
    App::Base::Script::Option->new(
      name => "foo",
      documentation => "The foo option",
      option_type => "integer",
      default => 7,
    ),
  ]);

Then in script_run() you can say

  my $foo = $self->getOption("foo")

And $foo will be resolved as follows:

1) A --foo value specified as a command-line switch
2) The default value specified at registration time ("bar")

=head1 BUILT-IN OPTIONS

=head2 --help

Print a usage statement

=head2 --log-facility=<f>

Use symbolic syslog facility <f> (default: 'local1'). See Sys::Syslog
for a list of known log facilities.

=head2 --quiet

Only print warning() and error() statements to STDERR. In other words,
do not print info() and notice() statements.

=head2 --verbose

Print debug() statements to STDERR, in addition to messages of all
other severity levels.

=head1 BUGS

No known bugs.

=head1 MAINTAINER

Nick Marden, <nick@regentmarkets.com>

=cut
