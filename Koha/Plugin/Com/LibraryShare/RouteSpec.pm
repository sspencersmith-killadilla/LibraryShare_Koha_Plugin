package Koha::Plugin::Com::LibraryShare::RouteSpec;
use strict;
use warnings;

# Mojolicious prepends its controller namespaces unless namespace is explicit.
# A fully-qualified class inside a "Class#method" shortcut is NOT sufficient.
sub normalise {
    my ($paths)=@_;
    for my $path (keys %$paths) {
        for my $verb (keys %{$paths->{$path}}) {
            my $operation=$paths->{$path}{$verb};
            next unless ref($operation) eq 'HASH';
            my $target=$operation->{'x-mojo-to'};
            next unless defined($target) && !ref($target);
            my ($controller,$action)=split /#/, $target,2;
            die "Invalid LibraryShare controller target" unless $controller && $action;
            $operation->{'x-mojo-to'}={
                namespace=>'',
                controller=>$controller,
                action=>$action,
            };
        }
    }
    return $paths;
}
1;
