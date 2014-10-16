use strict;
use warnings;

use Test::More (tests => 10);
use Test::NoWarnings;
use Test::Exit;
use Test::Exception;
use File::Temp;

use App::Base::Script;

sub divert_stderr {
    my $coderef = shift;
    local *STDERR;
    is(1, open(STDERR, ">/dev/null") ? 1 : 0, "Failed to redirect STDERR");
    &$coderef;
}

{

    package Test::Script;

    use Moose;
    with 'App::Base::Script';

    sub script_run {
        return 0;
    }

    sub documentation {
        return 'This is a test script.';
    }

    no Moose;
    __PACKAGE__->meta->make_immutable;
}

{

    package Test::Script::ThatDies;

    use Moose;
    extends 'Test::Script';

    sub script_run {
        die "I died";
    }

    no Moose;
    __PACKAGE__->meta->make_immutable;
}

{

    package Test::Script::OnlyOne;
    use Moose;
    extends 'Test::Script';
    with 'App::Base::Script::OnlyOne';

    sub script_run {
        sleep($ENV{ONLY_ONE_SLEEP} // 0);
        return 0;
    }

}

package main;

local %ENV = %ENV;
delete $ENV{COLUMNS};
my $sc = Test::Script->new;

my $switches = qq{--help             Show this help information                                 
--quiet            Do not print debugging or informational messages           
--verbose          Be very verbose with information and debugging messages         
};

my @switch_lines = split(/[\r\n]/, $switches);
my @output_lines = split(/[\r\n]/, $sc->switches);
$_ =~ s/\s+/ /g for @switch_lines;
$_ =~ s/\s+/ /g for @output_lines;
for (my $line = 0; $line < $#switch_lines; $line++) {
    is($switch_lines[$line], $output_lines[$line], "Switch output line " . ($line + 1) . " is correct");
}
is(0, $sc->run, 'Run returns 0');

divert_stderr(
    sub {
        HELP:
        {
            local @ARGV = ('--help');
            exits_ok(sub { Test::Script->new->run; }, "--help forces exit");
        }

        DEATH:
        {
            local @ARGV;
            exits_ok(sub { Test::Script::ThatDies->new->run; }, "die() in script causes exit");
        }

        ERROR:
        {
            exits_ok(
                sub {
                    my $script = Test::Script->new;
                    $script->error('This is really bad juju.');
                },
                "error() causes exit"
            );
        }
    },
);

$ENV{APP_BASE_DAEMON_PIDDIR} = File::Temp->newdir;

my $pid = fork;
die "Couldn't fork" unless defined $pid;

$ENV{ONLY_ONE_SLEEP} = 100;
if ($pid == 0) {
    Test::Script::OnlyOne->new->run;
    exit 0;
}

sleep 1;

my $pid2 = fork;
if ($pid2 == 0) {
    Test::Script::OnlyOne->new->run;
    exit 0;
}
$SIG{__DIE__} = sub { kill KILL => $pid2; };
$SIG{ALRM}    = sub { kill KILL => $pid2; };
waitpid $pid2, 0;
ok $?, "Can't run second copy of OnlyOne script";

kill KILL => $pid;
waitpid $pid, 0;

$ENV{ONLY_ONE_SLEEP} = 1;
is(Test::Script::OnlyOne->new->run, 0, "OnlyOne copy can run");

1;
