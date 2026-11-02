package Koha::Plugin::Com::LibraryShare::Controller::Static;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';

sub extended_js { _send_file($_[0],'static/extended.js','application/javascript; charset=utf-8') }
sub staff_js { _send_file($_[0],'static/staff.js','application/javascript; charset=utf-8') }
sub extended_css { _send_file($_[0],'static/extended.css','text/css; charset=utf-8') }

sub app_html {
    my ($c) = @_;
    return _send_file( $c, 'static/app.html', 'text/html; charset=utf-8' );
}

sub app_js {
    my ($c) = @_;
    return _send_file( $c, 'static/app.js', 'application/javascript; charset=utf-8' );
}

sub app_css {
    my ($c) = @_;
    return _send_file( $c, 'static/app.css', 'text/css; charset=utf-8' );
}

sub opac_js {
    my ($c) = @_;
    return _send_file( $c, 'static/libraryshare-opac.js', 'application/javascript; charset=utf-8' );
}

sub _send_file {
    my ( $c, $file, $content_type ) = @_;
    require Koha::Plugin::Com::LibraryShare;
    my $plugin = Koha::Plugin::Com::LibraryShare->new;
    return $c->render( status => 404, text => 'Plugin asset not found' ) unless $plugin;
    my $path = $plugin->mbf_path($file);
    open my $fh, '<:raw', $path or return $c->render( status => 404, text => 'Plugin asset not found' );
    local $/;
    my $body = <$fh>;
    close $fh;
    $c->res->headers->content_type($content_type);
    $c->res->headers->header( 'X-Content-Type-Options' => 'nosniff' );
    $c->res->headers->header( 'Cache-Control' => 'no-store, max-age=0' );
    $c->res->headers->header( 'X-LibraryShare-Version' => $Koha::Plugin::Com::LibraryShare::VERSION );
    return $c->render( status => 200, data => $body );
}

1;
