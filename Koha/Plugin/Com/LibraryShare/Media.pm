package Koha::Plugin::Com::LibraryShare::Media;
use Modern::Perl;
use C4::Context;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use File::Basename qw(basename);
use MIME::Base64 qw(decode_base64);
use Koha::Plugin::Com::LibraryShare::Controller::Extended;
sub directory {
    my ($create)=@_;my $base=C4::Context->config('upload_path');
    return unless $base && File::Spec->file_name_is_absolute($base);
    my $dir=File::Spec->catdir($base,'libraryshare');
    make_path($dir,{mode=>0700}) if $create && !-d $dir;
    return $dir;
}
sub fail {Koha::Plugin::Com::LibraryShare::Controller::Extended::fail(@_)}
sub t {Koha::Plugin::Com::LibraryShare::Stats::t($_[0])}
sub one {Koha::Plugin::Com::LibraryShare::Controller::Extended::one(@_)}
sub visible {
    my ($photo,$p)=@_;
    return 1 if $p && ($photo->{owner_borrowernumber}==$p->borrowernumber || Koha::Plugin::Com::LibraryShare::Controller::Extended::admin($p));
    return one('SELECT id FROM '.t('listings').' WHERE id=? AND status="active"',$photo->{listing_id}) if $photo->{listing_id};
    return one('SELECT id FROM '.t('reviews').' WHERE id=?',$photo->{review_id}) if $photo->{review_id};
    return;
}
sub remove {
    my ($photo)=@_;my $dir=directory(0);
    fail(503,'Photo storage is not configured.') unless $dir;
    fail(500,'Invalid media filename.') unless $photo->{storage_name}=~/\A[a-zA-Z0-9_.-]+\z/;
    my $file=File::Spec->catfile($dir,$photo->{storage_name});
    unlink($file) or fail(500,'Could not remove stored photo.') if -f $file;
    C4::Context->dbh->do('DELETE FROM '.t('photos').' WHERE id=?',undef,$photo->{id});
}
sub handle {
    my ($c,$p,$b,$post)=@_;my $db=C4::Context->dbh;
    if (!$post) {
        my ($col,$value)=$c->param('listing_id')?('listing_id',$c->param('listing_id')):('review_id',$c->param('review_id'));
        Koha::Plugin::Com::LibraryShare::Controller::Extended::id($value);
        my $rows=Koha::Plugin::Com::LibraryShare::Controller::Extended::rows('SELECT * FROM '.t('photos')." WHERE $col=? ORDER BY id",$value);
        my @out;
        for my $photo (@$rows) {
            next unless visible($photo,$p);
            delete $photo->{storage_name};$photo->{url}='/api/v1/contrib/libraryshare/media/'.$photo->{id};push @out,$photo;
        }
        return {photos=>\@out};
    }
    Koha::Plugin::Com::LibraryShare::Controller::Extended::require_user($p);
    if ($b->{remove}) {
        my $photo=one('SELECT * FROM '.t('photos').' WHERE id=?',Koha::Plugin::Com::LibraryShare::Controller::Extended::id($b->{id}));
        fail(404,'Photo not found.') unless $photo;
        fail(403,'Only the owner or library staff can remove this photo.') unless $photo->{owner_borrowernumber}==$p->borrowernumber || Koha::Plugin::Com::LibraryShare::Controller::Extended::admin($p);
        remove($photo);return {saved=>1};
    }
    fail(400,'Choose either a listing or a review.') if (!!$b->{listing_id}) == (!!$b->{review_id});
    my ($col,$value,$owner,$table)=$b->{listing_id}?('listing_id',$b->{listing_id},'owner_borrowernumber','listings'):('review_id',$b->{review_id},'reviewer_borrowernumber','reviews');
    my $target=one('SELECT * FROM '.t($table).' WHERE id=?',Koha::Plugin::Com::LibraryShare::Controller::Extended::id($value));
    fail(403,'You can only upload photos for your own items or reviews.') unless $target && $target->{$owner}==$p->borrowernumber;
    my ($count)=$db->selectrow_array('SELECT COUNT(*) FROM '.t('photos')." WHERE $col=?",undef,$value);
    fail(400,'Maximum six photos per item or review.') if $count>=6;
    my $encoded=$b->{data}//'';
    fail(400,'Photo is too large or invalid.') if ref($encoded) || length($encoded)>7000000;
    fail(400,'Upload JPEG, PNG or WebP images only.') unless $encoded=~m{\Adata:(image/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=\r\n]+)\z};
    my ($mime,$raw)=($1,decode_base64($2));
    fail(400,'Photo exceeds the 5 MB limit.') if length($raw)>5*1024*1024;
    my $valid=($mime eq 'image/jpeg' && substr($raw,0,3) eq "\xff\xd8\xff")
      || ($mime eq 'image/png' && substr($raw,0,8) eq "\x89PNG\r\n\x1a\n")
      || ($mime eq 'image/webp' && substr($raw,0,4) eq 'RIFF' && substr($raw,8,4) eq 'WEBP');
    fail(400,'Image content does not match its type.') unless $valid;
    my $dir=directory(1);fail(503,'Library staff must configure a writable Koha upload_path.') unless $dir && -w $dir;
    my ($fh,$path)=tempfile('photo-XXXXXXXXXXXX',DIR=>$dir,UNLINK=>0);
    binmode($fh);print {$fh} $raw or die 'Could not write photo';close($fh) or die 'Could not close photo';
    my $ok=eval {
        $db->do('INSERT INTO '.t('photos')." (owner_borrowernumber,$col,storage_name,mime,caption) VALUES (?,?,?,?,?)",undef,$p->borrowernumber,$value,basename($path),$mime,Koha::Plugin::Com::LibraryShare::Controller::Extended::text($b->{caption},200));1;
    };
    if (!$ok) {unlink $path;die $@}
    my ($id)=$db->selectrow_array('SELECT LAST_INSERT_ID()');
    return {id=>0+$id,url=>'/api/v1/contrib/libraryshare/media/'.$id};
}
sub serve {
    my ($c)=@_;my $id=$c->stash('photo_id')//'';
    return $c->render(status=>404,text=>'Photo not found') unless $id=~/\A\d+\z/;
    my $photo=one('SELECT * FROM '.t('photos').' WHERE id=?',$id);
    my $p=Koha::Plugin::Com::LibraryShare::Controller::Extended::actor($c);
    return $c->render(status=>404,text=>'Photo not found') unless $photo && visible($photo,$p);
    my $dir=directory(0);
    return $c->render(status=>404,text=>'Photo not found') unless $dir && $photo->{storage_name}=~/\A[a-zA-Z0-9_.-]+\z/;
    open my $fh,'<:raw',File::Spec->catfile($dir,$photo->{storage_name}) or return $c->render(status=>404,text=>'Photo not found');
    local $/;my $bytes=<$fh>;close $fh;
    $c->res->headers->content_type($photo->{mime});
    $c->res->headers->header('X-Content-Type-Options'=>'nosniff');
    $c->res->headers->header('Cache-Control'=>'private, no-store');
    $c->res->headers->header('Content-Security-Policy'=>"default-src 'none'; sandbox");
    return $c->render(data=>$bytes);
}
1;
