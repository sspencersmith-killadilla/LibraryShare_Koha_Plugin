package Koha::Plugin::Com::LibraryShare::Navigation;
use strict;
use warnings;
use URI;

sub public_base {
    require C4::Context;
    my $value=C4::Context->preference('OPACBaseURL') // '';
    my $uri=URI->new($value);
    return '' unless ($uri->scheme//'') =~ /\Ahttps?\z/ && $uri->host
        && !$uri->userinfo && !$uri->query && !$uri->fragment;
    $value =~ s{/$}{};
    return $value;
}
sub links {
    my ($c)=@_;
    my $base=public_base();
    my $origin=$c->req->url->to_abs;
    my $public=$base && lc($origin->host//'') eq lc(URI->new($base)->host//'')
        && URI->new("$origin")->port == URI->new($base)->port;
    # Unknown hosts default to staff navigation, never to an OPAC CGI on staff.
    return {
        public_url=>$base ? "$base/api/v1/contrib/libraryshare/static/app.html" : '',
        account_url=>!$base ? '' : $public ? "$base/cgi-bin/koha/opac-user.pl" : '/cgi-bin/koha/mainpage.pl',
        context=>$public ? 'public' : 'staff',
        configuration_error=>$base ? '' : 'Staff must configure a valid OPACBaseURL in Koha system preferences.',
    };
}
1;
