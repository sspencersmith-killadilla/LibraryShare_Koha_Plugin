package Koha::Plugin::Com::LibraryShare::Administration;
use Modern::Perl;
use Koha::Plugin::Com::LibraryShare::Controller::Extended;
use Koha::Plugin::Com::LibraryShare::Media;
sub t {Koha::Plugin::Com::LibraryShare::Stats::t($_[0])}
sub rows {Koha::Plugin::Com::LibraryShare::Controller::Extended::rows(@_)}
sub one {Koha::Plugin::Com::LibraryShare::Controller::Extended::one(@_)}
sub fail {Koha::Plugin::Com::LibraryShare::Controller::Extended::fail(@_)}
sub handle {
    my ($c,$p,$b,$post)=@_;
    Koha::Plugin::Com::LibraryShare::Controller::Extended::require_admin($p);
    my $db=C4::Context->dbh;
    if ($post) {
        my $id=Koha::Plugin::Com::LibraryShare::Controller::Extended::id($b->{id});
        my $entity=$b->{entity}//'';my $action=$b->{action}//'';
        my $reason=Koha::Plugin::Com::LibraryShare::Controller::Extended::text($b->{reason},2000);
        fail(400,'An explanation is required for moderation.') unless $reason=~/\S/;
        if ($entity eq 'listing') {
            fail(400,'Unknown listing action.') unless $action=~/\A(?:remove|restore)\z/;
            my $l=one('SELECT * FROM '.t('listings').' WHERE id=?',$id);fail(404,'Listing not found.') unless $l;
            fail(409,'Return the active checkout before removing its listing.') if one('SELECT issue_id FROM issues WHERE itemnumber=?',$l->{itemnumber});
            $db->do('UPDATE '.t('listings').' SET status=? WHERE id=?',undef,$action eq 'remove'?'removed':'active',$id);
        } elsif ($entity eq 'role') {
            require C4::Auth;
            fail(403,'Only a Koha plugin manager can grant or revoke LibraryShare administrators.') unless C4::Auth::haspermission($p->userid,{plugins=>'manage'});
            fail(400,'Unknown role action.') unless $action=~/\A(?:grant|revoke)\z/;
            fail(404,'Patron not found.') unless one('SELECT borrowernumber FROM borrowers WHERE borrowernumber=?',$id);
            if ($action eq 'grant') {$db->do('INSERT IGNORE INTO '.t('roles').' (borrowernumber) VALUES (?)',undef,$id)}
            else {$db->do('DELETE FROM '.t('roles').' WHERE borrowernumber=?',undef,$id)}
        } elsif ($entity eq 'photo') {
            fail(400,'Unknown photo action.') unless $action eq 'remove';
            my $ph=one('SELECT * FROM '.t('photos').' WHERE id=?',$id);fail(404,'Photo not found.') unless $ph;
            Koha::Plugin::Com::LibraryShare::Media::remove($ph);
        } elsif ($entity eq 'review' || $entity eq 'kudos') {
            fail(400,'Unknown moderation action.') unless $action eq 'remove';
            my $table=$entity eq 'review'?'reviews':'kudos';
            my $row=one('SELECT * FROM '.t($table).' WHERE id=?',$id);fail(404,'Record not found.') unless $row;
            if ($entity eq 'review') {Koha::Plugin::Com::LibraryShare::Media::remove($_) for @{rows('SELECT * FROM '.t('photos').' WHERE review_id=?',$id)}}
            $db->do('DELETE FROM '.t($table).' WHERE id=?',undef,$id);
            Koha::Plugin::Com::LibraryShare::Stats::recompute($row->{$entity eq 'review'?'reviewee_borrowernumber':'recipient_borrowernumber'});
        } else {fail(400,'Unknown moderation entity.')}
        Koha::Plugin::Com::LibraryShare::Controller::Extended::audit($p,"$entity:$action",$id,$reason);
        return {saved=>1};
    }
    my $photos=rows('SELECT id,owner_borrowernumber,listing_id,review_id,mime,caption,created_at FROM '.t('photos').' ORDER BY id DESC LIMIT 500');
    $_->{url}='/api/v1/contrib/libraryshare/media/'.$_->{id} for @$photos;
    return {
      listings=>rows('SELECT * FROM '.t('listings').' ORDER BY id DESC LIMIT 1000'),
      reviews=>rows('SELECT * FROM '.t('reviews').' ORDER BY id DESC LIMIT 1000'),photos=>$photos,
      users=>rows('SELECT b.borrowernumber,b.firstname,b.surname,COALESCE(r.role,"member") AS role FROM borrowers b LEFT JOIN '.t('roles').' r ON r.borrowernumber=b.borrowernumber WHERE b.borrowernumber IN (SELECT owner_borrowernumber FROM '.t('listings').' UNION SELECT borrower_borrowernumber FROM '.t('borrow_requests').' UNION SELECT borrowernumber FROM '.t('roles').') ORDER BY b.surname LIMIT 1000'),
      reports=>rows('SELECT * FROM '.t('reports').' ORDER BY id DESC LIMIT 1000'),
      audit=>rows('SELECT * FROM '.t('audit').' ORDER BY id DESC LIMIT 500'),
      challenges=>rows('SELECT * FROM '.t('challenges').' ORDER BY start_date DESC'),
      badges=>rows('SELECT * FROM '.t('badge_definitions').' ORDER BY slug'),
      kudos=>rows('SELECT * FROM '.t('kudos').' ORDER BY id DESC LIMIT 500')
    };
}
1;
