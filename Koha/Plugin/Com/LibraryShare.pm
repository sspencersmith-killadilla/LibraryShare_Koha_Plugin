package Koha::Plugin::Com::LibraryShare;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use C4::Context;

use JSON qw(decode_json);
use Koha::Plugin::Com::LibraryShare::RouteSpec;

our $VERSION = '0.2.8';
our $metadata = {
    name            => 'LibraryShare',
    author          => 'LibraryShare contributors',
    date_authored   => '2026-11-02',
    date_updated    => '2026-11-02',
    minimum_version => '26.05',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Peer-to-peer lending of patron-owned items through Koha.',
};

sub new {
    my ($class,$args)=@_;
    $args //= {};
    $args->{metadata}={%$metadata};
    return $class->SUPER::new($args);
}

sub install {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;
    for my $file ('install.sql','extensions.sql') {
        my $sql=$self->mbf_read($file);
        for my $statement ( split /;\s*(?:\n|\z)/, $sql ) {
            $statement =~ s/^\s+|\s+$//g;
            next unless $statement;
            $dbh->do($statement);
        }
    }
    require Koha::Plugin::Com::LibraryShare::Value;
    Koha::Plugin::Com::LibraryShare::Value::migrate($dbh);
    return 1;
}

sub upgrade {
    my ($self) = @_;
    return $self->install;
}

sub uninstall {
    my ($self) = @_;
    # Keep user and circulation history by default. Administrators can remove
    # plugin tables explicitly after exporting data if they choose to uninstall.
    return 1;
}

sub api_namespace { return 'libraryshare'; }

sub api_routes {
    my ($self) = @_;
    my $spec = decode_json( $self->mbf_read('openapi.json') );
    my $extra = decode_json( $self->mbf_read('extendedapi.json') );
    @{$spec->{paths}}{keys %{$extra->{paths}}}=values %{$extra->{paths}};
    Koha::Plugin::Com::LibraryShare::RouteSpec::normalise($spec->{paths});
    return $spec->{paths};
}

sub static_routes {
    my ($self) = @_;
    my $spec = decode_json( $self->mbf_read('staticapi.json') );
    Koha::Plugin::Com::LibraryShare::RouteSpec::normalise($spec->{paths});
    return $spec->{paths};
}

sub opac_js {
    return qq{<script defer src="/api/v1/contrib/libraryshare/static/libraryshare-opac.js?v=$VERSION"></script>};
}

sub tool {
    my ($self) = @_;
    my $template = $self->get_template( { file => 'templates/admin.tt' } );
    $template->param(
        public_url => do {
            require Koha::Plugin::Com::LibraryShare::Navigation;
            my $base=Koha::Plugin::Com::LibraryShare::Navigation::public_base();
            $base ? "$base/api/v1/contrib/libraryshare/static/app.html?v=$VERSION" : '';
        },
        api_base => '/api/v1/contrib/libraryshare',
        plugin_name => 'LibraryShare',
        plugin_version => $VERSION,
    );
    return $self->output_html( $template->output );
}

1;
