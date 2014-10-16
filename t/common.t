use strict;
use warnings;

use Test::More (tests => 22);
use Test::NoWarnings;
use Test::Warn;
use Test::Exit;
use Test::Exception;
use Text::Trim;

sub divert_stderr {
    my $coderef = shift;
    local *STDERR;
    is(1, open(STDERR, ">/dev/null") ? 1 : 0, "Failed to redirect STDERR");
    &$coderef;
}

use App::Base::Script::Common;

package Test::Script::Common;

use Moose;
with 'App::Base::Script::Common';

sub __run {
    my ($self) = @_;
    $self->notice('in the past logging at the end of a script has caused false failures');
}

sub documentation {
    return 'This is a test script.';
}

around 'base_options' => sub {
    my $orig = shift;
    my $self = shift;
    return [
        @{$self->$orig},
        App::Base::Script::Option->new({
                name          => 'foo',
                display       => 'foo=<f>',
                documentation => 'The foo option should be <f>',
                option_type   => 'string',
                default       => 'bar',
            }
        ),
        App::Base::Script::Option->new({
                name          => 'baz',
                documentation => 'The baz option',
                option_type   => 'switch',
            }
        ),
        App::Base::Script::Option->new({
                name          => 'quux',
                display       => 'quux=N',
                documentation => 'quux is an integer option',
                option_type   => 'integer',
                default       => 7,
            }
        ),
        App::Base::Script::Option->new({
                name          => 'fribitz',
                display       => 'fribitz=<f>',
                documentation => 'fribitz is a floating-point option',
                option_type   => 'float',
                default       => 0.01,
            }
        ),
    ];
};

sub error {
    my $self = shift;
    open(ERR, ">/dev/null");
    print ERR @_;
    close ERR;
    exit 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

package main;

local %ENV = %ENV;
# ensure we run the tests using the default value.
delete $ENV{COLUMNS};

my $sc = Test::Script::Common->new;

my $switches = qq{--baz              The baz option                                             
--foo=<f>          The foo option should be <f> (default: bar)                
--fribitz=<f>      fribitz is a floating-point option (default: 0.01)         
--help             Show this help information                                 
--quiet            Do not print debugging or informational messages           
--quux=N           quux is an integer option (default: 7)                     
--verbose          Be very verbose with information and debugging messages
};
my $scswitches = $sc->switches;
$scswitches =~ s/\s+/ /g;
$switches   =~ s/\s+/ /g;

is($sc->getOption('help'), undef,           'help was not requested');
is($sc->run,               0,               'run() returns 0');
is($sc->script_name,       'common.t',      'script_name() returns correct value');
is(trim($scswitches),      trim($switches), 'switches() returns correct value');
divert_stderr(
    sub {
        ok($sc->warning('warning message'), 'warning() returns true');

# Exercise both the has_tty and not has_tty paths for coverage
        $sc->has_tty(0);
        ok($sc->warning('warning message'), 'warning() returns true');
        $sc->has_tty(1);
        ok($sc->warning('warning message'), 'warning() returns true');
        exits_ok(sub { $sc->usage; }, "usage() method causes exit");
        exits_ok(sub { $sc->__error("Error message"); }, "__error() method causes exit");
        throws_ok { $sc->getOption('bogus_option'); } qr/Unknown option/, 'Bogus option names cause death';

        STDERR->autoflush(0);
        $sc->has_tty(1);
        is($sc->run,          0, 'Run returns 0');
        is(STDERR->autoflush, 1, 'STDERR autoflush is turned on if has_tty is true');

        STDERR->autoflush(0);
        $sc->has_tty(0);
        is($sc->run,          0, 'Run returns 0');
        is(STDERR->autoflush, 0, 'STDERR autoflush is not turned on if has_tty is true');

        COLUMNS:
        {
            my $long_switches = qq{--baz              The baz option                                                                     
--foo=<f>          The foo option should be <f> (default: bar)                                        
--fribitz=<f>      fribitz is a floating-point option (default: 0.01)                                 
--help             Show this help information                                                         
--quiet            Do not print debugging or informational messages                                   
--quux=N           quux is an integer option (default: 7)                                             
--verbose          Be very verbose with information and debugging messages
};

            local %ENV;
            $ENV{COLUMNS} = 100;
            $long_switches =~ s/\s+/ /g;
            is(trim($long_switches), trim($scswitches), 'COLUMNS environment variable controls width of switch table output');
        }

        HELP:
        {
            local @ARGV = ('--help');
            exits_ok(sub { Test::Script::Common->new; }, "--help forces exit");
        }

        NONSENSE:
        {
            local @ARGV = ('--nonsense-option');
            warnings_like {
                exits_ok(sub { Test::Script::Common->new; }, "Can't instantiate a script with an invalid option");
            }
            qr/Unknown option/, 'Unknown option warns';
        }

        INVALID_OPTION_VALUE:
        {
            local @ARGV = ('--quux=a_string');
            warnings_like {
                exits_ok(sub { Test::Script::Common->new; },
                    "Can't instantiate a script with an option value that does not match the specified type");
            }
            qr/invalid for option quux/, 'option with invalid type warns';
        }
    });

1;
