package Koha::Plugin::Com::LibraryShare::Stats;
use Modern::Perl;
use C4::Context;
use Koha::Plugin::Com::LibraryShare::Value;
use POSIX qw(strftime);
sub t { 'koha_plugin_com_libraryshare_' . $_[0] }
sub setting {
    my ($key,$default)=@_;
    my ($v)=C4::Context->dbh->selectrow_array('SELECT setting_value FROM '.t('settings').' WHERE setting_key=?',undef,$key);
    return defined($v) ? $v : $default;
}
sub award {
    my ($pid,$delta,$reason,$key,$request)=@_;
    return unless $delta;
    my $db=C4::Context->dbh;
    # Preserve awards from pre-extension installations.
    return if $request && $db->selectrow_array('SELECT id FROM '.t('share_credits_ledger').' WHERE patron_borrowernumber=? AND related_request_id=? AND reason=?',undef,$pid,$request,$reason);
    require Koha::Database;
    Koha::Database->new->schema->txn_do(sub {
    my $inserted=$db->do('INSERT IGNORE INTO '.t('credit_events').' (event_key,patron_id,delta) VALUES (?,?,?)',undef,$key,$pid,$delta);
    if ($inserted && $inserted ne '0E0') {
        $db->do('INSERT INTO '.t('share_credits_ledger').' (patron_borrowernumber,delta,reason,related_request_id) VALUES (?,?,?,?)',undef,$pid,$delta,$reason,$request);
    }
    });
}
sub metrics {
    my ($pid)=@_;
    my $db=C4::Context->dbh;
    my $rows=$db->selectall_arrayref('SELECT r.*,l.category,l.estimated_value, TIMESTAMPDIFF(DAY,r.created_at,r.due_date) AS duration FROM '.t('borrow_requests').' r JOIN '.t('listings').' l ON l.id=r.listing_id WHERE r.status="returned" AND (r.owner_borrowernumber=? OR r.borrower_borrowernumber=?)',{Slice=>{}},$pid,$pid);
    my %m=map {$_=>0} qw(loans_as_lender loans_as_borrower distinct_items_lent distinct_categories_lent distinct_categories_borrowed on_time_returns longest_loan_days est_value_saved kudos_count avg_rating_lender avg_rating_borrower perfect_streak category_specialist wishes_fulfilled careful_custodian community_pillar streak_months_lender);
    my (%items,%cats,%borrowed,%months);
    for my $r (@$rows) {
        if ($r->{owner_borrowernumber}==$pid) {
            $m{loans_as_lender}++;$items{$r->{listing_id}}++;$cats{$r->{category}}++;
            $months{substr($r->{returned_at}//'',0,7)}++;
            $m{longest_loan_days}=$r->{duration} if ($r->{duration}//0)>$m{longest_loan_days};
            $m{est_value_saved}+=Koha::Plugin::Com::LibraryShare::Value::half($r->{estimated_value})//0;
        } else {
            $m{loans_as_borrower}++;$borrowed{$r->{category}}++;
            $m{on_time_returns}++ if $r->{returned_at} && $r->{due_date} && $r->{returned_at} le $r->{due_date};
        }
    }
    $m{distinct_items_lent}=scalar keys %items;$m{distinct_categories_lent}=scalar keys %cats;$m{distinct_categories_borrowed}=scalar keys %borrowed;
    for (values %cats) {$m{category_specialist}=$_ if $_>$m{category_specialist}}
    my @now=localtime;my ($year,$month)=($now[5]+1900,$now[4]+1);
    while ($months{sprintf('%04d-%02d',$year,$month)}) {$m{streak_months_lender}++;$month--;if (!$month){$month=12;$year--}}
    for my $role (qw(lender borrower)) {
        my $col=$role eq 'lender'?'owner_borrowernumber':'borrower_borrowernumber';
        ($m{"avg_rating_$role"})=$db->selectrow_array('SELECT COALESCE(AVG(v.rating),0) FROM '.t('reviews').' v JOIN '.t('borrow_requests')." r ON r.id=v.request_id WHERE v.reviewee_borrowernumber=? AND r.$col=?",undef,$pid,$pid);
    }
    my $ratings=$db->selectcol_arrayref('SELECT v.rating FROM '.t('reviews').' v JOIN '.t('borrow_requests').' r ON r.id=v.request_id WHERE v.reviewee_borrowernumber=? AND r.owner_borrowernumber=? ORDER BY v.created_at DESC LIMIT 10',undef,$pid,$pid);
    for (@$ratings) {last if $_!=5;$m{perfect_streak}++}
    ($m{kudos_count})=$db->selectrow_array('SELECT COUNT(*) FROM '.t('kudos').' WHERE recipient_borrowernumber=?',undef,$pid);
    ($m{wishes_fulfilled})=$db->selectrow_array('SELECT COUNT(*) FROM '.t('fulfilments').' WHERE lender=?',undef,$pid);
    # Reports are listing-level disputes: include any reported listing borrowed by this member.
    my ($disputes)=$db->selectrow_array('SELECT COUNT(*) FROM '.t('reports').' p JOIN '.t('borrow_requests').' r ON r.listing_id=p.listing_id WHERE r.borrower_borrowernumber=? AND p.status<>"dismissed"',undef,$pid);
    $m{careful_custodian}=$disputes?0:$m{loans_as_borrower};
    my $ranked=$db->selectall_arrayref('SELECT owner_borrowernumber,COUNT(*) AS n FROM '.t('borrow_requests').' WHERE status="returned" AND returned_at>=DATE_SUB(NOW(),INTERVAL 30 DAY) GROUP BY owner_borrowernumber ORDER BY n DESC,owner_borrowernumber',{Slice=>{}});
    my $top=int((scalar(@$ranked)+9)/10);
    for my $i (0..$top-1) {$m{community_pillar}=1 if $ranked->[$i]{owner_borrowernumber}==$pid}
    return (\%m,$rows);
}
sub levels {
    my ($m)=@_;
    my ($l,$b)=('newcomer','newcomer');
    for my $tier (['contributor',3,4],['steward',10,4.3],['champion',25,4.5],['pillar',60,4.7]) {
        $l=$tier->[0] if $m->{loans_as_lender}>=$tier->[1] && $m->{avg_rating_lender}>=$tier->[2];
    }
    $b='reliable' if $m->{loans_as_borrower}>=5;
    $b='trusted' if $m->{loans_as_borrower}>=15 && $m->{avg_rating_borrower}>=4.5;
    return {lender=>$l,borrower=>$b};
}
sub recompute {
    my ($pid)=@_;my $db=C4::Context->dbh;
    my ($m,$rows)=metrics($pid);
    if (setting('gamification_enabled',1)) {
        for my $r (@$rows) {
            if ($r->{owner_borrowernumber}==$pid) {award($pid,setting('credits_per_completed_loan',10),'loan_completed',"loan:$r->{id}:$pid",$r->{id})}
            elsif ($r->{returned_at} && $r->{due_date} && $r->{returned_at} le $r->{due_date}) {award($pid,setting('credits_per_on_time_return',2),'on_time_return',"ontime:$r->{id}:$pid",$r->{id})}
        }
        my ($first)=$db->selectrow_array('SELECT MIN(id) FROM '.t('listings').' WHERE owner_borrowernumber=?',undef,$pid);
        award($pid,setting('credits_first_listing',15),'first_listing',"first:$pid") if $first;
        for my $k (@{$db->selectcol_arrayref('SELECT id FROM '.t('kudos').' WHERE recipient_borrowernumber=?',undef,$pid)}) {award($pid,setting('credits_per_kudos',3),'kudos_received',"kudos:$k")}
        for my $w (@{$db->selectcol_arrayref('SELECT wanted_id FROM '.t('fulfilments').' WHERE lender=?',undef,$pid)}) {award($pid,setting('credits_wanted_fulfilled',20),'wanted_fulfilled',"wish:$w")}
        for my $def (@{$db->selectall_arrayref('SELECT * FROM '.t('badge_definitions').' WHERE active=1',{Slice=>{}})}) {
            if (($m->{$def->{metric}}//0)>=$def->{threshold}) {$db->do('INSERT IGNORE INTO '.t('badges').' (borrowernumber,badge_key) VALUES (?,?)',undef,$pid,$def->{slug})}
        }
        for my $ch (@{$db->selectall_arrayref('SELECT * FROM '.t('challenges').' WHERE active=1',{Slice=>{}})}) {
            my $n=grep {$_->{owner_borrowernumber}==$pid && substr($_->{returned_at}//'',0,10) ge $ch->{start_date} && substr($_->{returned_at}//'',0,10) le $ch->{end_date}} @$rows;
            $db->do('INSERT INTO '.t('challenge_progress').' (challenge_id,borrowernumber,progress,completed_at) VALUES (?,?,?,IF(? >= ?,NOW(),NULL)) ON DUPLICATE KEY UPDATE progress=VALUES(progress),completed_at=IF(VALUES(progress)>=?,COALESCE(completed_at,NOW()),NULL)',undef,$ch->{id},$pid,$n,$n,$ch->{goal},$ch->{goal});
        }
    }
    ($m->{share_credits})=$db->selectrow_array('SELECT COALESCE(SUM(delta),0) FROM '.t('share_credits_ledger').' WHERE patron_borrowernumber=?',undef,$pid);
    $m->{level}=levels($m)->{lender};
    my @cols=qw(loans_as_lender loans_as_borrower distinct_items_lent est_value_saved share_credits);
    $db->do('INSERT IGNORE INTO '.t('patron_stats').' (borrowernumber) VALUES (?)',undef,$pid);
    $db->do('UPDATE '.t('patron_stats').' SET '.join(',',map {"$_=?"} @cols).' WHERE borrowernumber=?',undef,(map {$m->{$_}} @cols),$pid);
    return $m;
}
sub reconcile {
    my $db=C4::Context->dbh;
    require Koha::Database;
    my $open=$db->selectall_arrayref('SELECT * FROM '.t('borrow_requests').' WHERE status="approved"',{Slice=>{}});
    for my $r (@$open) {
        my $key="libraryshare:listing:$r->{listing_id}";
        my ($locked)=$db->selectrow_array('SELECT GET_LOCK(?,5)',undef,$key);
        next unless $locked;
        my $ok=eval {
            Koha::Database->new->schema->txn_do(sub {
                my ($returned)=$db->selectrow_array('SELECT returndate FROM old_issues WHERE issue_id=? AND borrowernumber=?',undef,$r->{checkout_id},$r->{borrower_borrowernumber});
                return unless $returned;
                my $changed=$db->do('UPDATE '.t('borrow_requests').' SET status="returned",returned_at=? WHERE id=? AND status="approved"',undef,$returned,$r->{id});
                if ($changed && $changed ne '0E0') {
                    $db->do('INSERT INTO '.t('handoff_events').' (request_id,actor_borrowernumber,event_kind,note) VALUES (?,?,"returned","Reconciled from Koha circulation history")',undef,$r->{id},$r->{owner_borrowernumber});
                }
            });1;
        };
        my $error=$@;
        $db->selectrow_array('SELECT RELEASE_LOCK(?)',undef,$key);
        die $error unless $ok;
    }
    my $ids=$db->selectcol_arrayref('SELECT owner_borrowernumber FROM '.t('listings').' UNION SELECT borrower_borrowernumber FROM '.t('borrow_requests'));
    recompute($_) for @$ids;
    return scalar @$ids;
}
1;
