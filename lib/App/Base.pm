package App::Base;
use strict;
use warnings;
our $VERSION = "0.05";
$VERSION = eval $VERSION;

=head1 NAME

App::Base - modules implementing common methods for applications

=head1 VERSION

This document describes App::Base version 0.05

=head1 SYNOPSIS

    use App::Base;

=head1 DESCRIPTION

This distribution provides modules that implement common methods for writing scripts and daemons.

=over 4

=item L<App::Base::Script>

Role implementing basic functionality for scripts

=item L<App::Base::Script::OnlyOne>

Role to allow only one running instance of the script

=item L<App::Base::Daemon>

Role implementing basic functionality for daemons

=item L<App::Base::Daemon::Supervisor>

Role implementing methods to support supervision and zero downtime reloading for daemons.

=back

=cut

1;

__END__

=head1 CONTRIBUTORS

The following people contributed to this module:

=over 4

=item Calum Halcrow

=item Chris Travers

=item Fayland Lam

=item Jean-Yves Sireau

=item Kaveh Mousavi Zamani

=item Matt Miller

=item Nick Marden

=item Pavel Shaydo

=item Tee Shuwn Yuan

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2010-2014 Binary.com

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
