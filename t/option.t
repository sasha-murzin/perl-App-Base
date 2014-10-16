use strict;
use warnings;

use Test::More (tests => 6);
use Test::NoWarnings;
use Test::Exception;

use App::Base::Script::Option;

my $o = App::Base::Script::Option->new({
        name          => 'foo',
        documentation => 'The foo option',
});
is('foo',            $o->name,          "name is set correctly");
is(undef,            $o->display,       "display is undef");
is('The foo option', $o->documentation, "documentation is set correctly");
is('switch',         $o->option_type,   "option_type is set correctly");
is(undef,            $o->default,       "default is undef");

1;
