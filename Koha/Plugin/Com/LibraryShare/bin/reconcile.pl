#!/usr/bin/perl
use strict;
use warnings;
use Koha::Plugin::Com::LibraryShare::Stats;
# Run as the Koha instance user with its KOHA_CONF and PERL5LIB environment.
my $count=Koha::Plugin::Com::LibraryShare::Stats::reconcile();
print "LibraryShare reconciled circulation and refreshed $count member accounts.\n";
