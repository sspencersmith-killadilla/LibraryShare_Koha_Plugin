package Koha::Plugin::Com::LibraryShare::Controller::Extended;
use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::LibraryShare::Controller::API;
use Koha::Plugin::Com::LibraryShare::Stats;
use JSON qw(encode_json decode_json);
use Try::Tiny;
sub db { C4::Context->dbh }
sub t { Koha::Plugin::Com::LibraryShare::Stats::t($_[0]) }
sub actor { Koha::Plugin::Com::LibraryShare::Controller::API::_patron($_[0]) }
sub admin { Koha::Plugin::Com::LibraryShare::Controller::API::_is_admin($_[0]) }
sub fail { die {status=>$_[0],error=>$_[1]} }
sub id { my ($v)=@_;fail(400,'A positive numeric identifier is required.') unless defined($v) && !ref($v) && $v=~/\A[1-9]\d*\z/;return 0+$v }
sub text { my ($v,$max)=@_;fail(400,'Invalid text value.') if ref($v);$v//='';fail(400,'Text exceeds the allowed length.') if length($v)>$max;return $v }
sub rows {my ($sql,@bind)=@_;db()->selectall_arrayref($sql,{Slice=>{}},@bind)}
sub one {my ($sql,@bind)=@_;db()->selectrow_hashref($sql,undef,@bind)}
sub audit {
    my ($p,$action,$target,$note)=@_;
    db()->do('INSERT INTO '.t('audit').' (actor,action,target,note) VALUES (?,?,?,?)',undef,$p->borrowernumber,$action,$target,substr($note//'',0,2000));
}
sub pending {
    my ($pid)=@_;
    return rows('SELECT d.* FROM '.t('documents').' d WHERE d.required=1 AND NOT EXISTS (SELECT 1 FROM '.t('legal_acceptances').' a WHERE a.borrowernumber=? AND a.document_key=d.document_key AND a.document_version=d.version)',$pid);
}
sub dispatch {
    my ($c)=@_;my $area=$c->stash('area')//'';
    my %handlers=(config=>\&config,agreements=>\&agreements,documents=>\&documents,profile=>\&profile,
        facets=>\&facets,availability=>\&availability,history=>\&history,matches=>\&matches,fulfil=>\&fulfil,
        reports=>\&reports,notifications=>\&notifications,impact=>\&impact,credits=>\&credits,
        badges=>\&badges,challenges=>\&challenges,diagnostics=>\&diagnostics,admin=>\&administration,photos=>\&photos);
    return $c->render(status=>404,json=>{error=>'Unknown LibraryShare endpoint.'}) unless $handlers{$area};
    my $p=actor($c);my $post=$c->req->method eq 'POST';
    if ($post) {$p=Koha::Plugin::Com::LibraryShare::Controller::API::_need_patron($c) or return}
    my $body=$post?($c->req->json//{}):{};
    return $c->render(status=>400,json=>{error=>'A JSON object is required.'}) unless ref($body) eq 'HASH';
    try {
        my $data=$handlers{$area}->($c,$p,$body,$post);
        $c->render(status=>200,json=>$data//{saved=>1});
    } catch {
        if (ref($_) eq 'HASH') {$c->render(status=>$_->{status},json=>{error=>$_->{error}})}
        else {$c->app->log->error("LibraryShare $area: $_");$c->render(status=>500,json=>{error=>'LibraryShare could not complete this operation. Ask library staff to check the server log.'})}
    };
}
sub require_user { fail(401,'Sign in to your Koha account.') unless $_[0] }
sub require_admin { require_user($_[0]);fail(403,'LibraryShare administration permission required.') unless admin($_[0]) }
sub settings {
    my %s=(gamification_enabled=>1,credits_per_completed_loan=>10,credits_per_kudos=>3,credits_first_listing=>15,
      credits_per_on_time_return=>2,credits_wanted_fulfilled=>20,priority_threshold=>30,longer_loan_threshold=>50,
      longer_loan_bonus_days=>7,fast_track_min_on_time=>3,early_access_threshold=>25,early_access_hours=>24,
      borrow_credit_cost=>0,starting_credits=>0,max_active_requests=>10,featured_lender=>0,community_goal=>100,milestone_loans=>100,
      item_type_code=>'PEERLEND',default_loan_days=>14);
    for (@{rows('SELECT * FROM '.t('settings'))}) {$s{$_->{setting_key}}=$_->{setting_value} if exists $s{$_->{setting_key}}}
    return \%s;
}
sub config {
    my ($c,$p,$b,$post)=@_;
    if ($post) {
        require_admin($p);
        if (exists $b->{branding}) {
            fail(400,'Branding must be an object.') unless ref($b->{branding}) eq 'HASH';
            my %brand;
            if (exists $b->{branding}{custom_css}) {$brand{custom_css}=text($b->{branding}{custom_css},20000)}
            my %choices=(
              theme_preset=>[qw(sunny ocean forest)],font_style=>[qw(friendly classic system)],
              corner_style=>[qw(rounded square)],density=>[qw(comfortable compact)]
            );
            for my $key (keys %choices) {
                next unless exists $b->{branding}{$key};
                my $value=text($b->{branding}{$key},40);
                fail(400,"Invalid $key choice.") unless grep {$_ eq $value} @{$choices{$key}};
                $brand{$key}=$value;
            }
            for my $k (qw(name site_name tagline primary_color accent_color background_color foreground_color homepage_hero_title homepage_hero_body footer_text logo_url favicon_url koha_public_url library_website_url)) {
                next unless exists $b->{branding}{$k};
                my $v=text($b->{branding}{$k},2000);
                fail(400,'Colors must use six hexadecimal digits.') if $k=~/_color$/ && $v !~ /\A#[0-9a-fA-F]{6}\z/;
                fail(400,'Use an HTTPS or same-site asset URL.') if $k=~/_url$/ && length($v) && $v !~ m{\A(?:https://|/(?!/))};
                $brand{$k}=$v;
            }
            db()->do('INSERT INTO '.t('settings').' (setting_key,setting_value) VALUES ("branding",?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)',undef,encode_json(\%brand));
        }
        if (exists $b->{settings}) {
            fail(400,'Settings must be an object.') unless ref($b->{settings}) eq 'HASH';
            my $allowed=settings();
            for my $k (keys %{$b->{settings}}) {
                fail(400,'Unsupported setting.') unless exists $allowed->{$k};
                my $v=$b->{settings}{$k};
                if ($k eq 'item_type_code') {
                    fail(400,'Unknown Koha item type.') unless !ref($v) && one('SELECT itemtype FROM itemtypes WHERE itemtype=?',$v);
                } else {
                    fail(400,'Settings require a nonnegative integer, at most 1000000.') unless defined($v) && "$v"=~/\A\d+\z/ && $v<=1000000;
                    fail(400,'Loan period must be between 1 and 90 days.') if $k eq 'default_loan_days' && ($v<1 || $v>90);
                }
                db()->do('INSERT INTO '.t('settings').' (setting_key,setting_value) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)',undef,$k,$v);
            }
        }
        audit($p,'config','settings','Updated LibraryShare configuration');
    }
    my $branding=one('SELECT setting_value FROM '.t('settings').' WHERE setting_key="branding"');
    return {branding=>$branding?decode_json($branding->{setting_value}):{name=>'LibraryShare',tagline=>'Your library card, now for everything else.',theme_preset=>'sunny',font_style=>'friendly',corner_style=>'rounded',density=>'comfortable'},
        documents=>rows('SELECT * FROM '.t('documents').' ORDER BY document_key'),settings=>settings(),is_admin=>admin($p)?1:0,
        preferences=>$p?(one('SELECT show_in_leaderboard FROM '.t('preferences').' WHERE borrowernumber=?',$p->borrowernumber)//{show_in_leaderboard=>1}):{show_in_leaderboard=>1}};
}
sub documents {
    my ($c,$p,$b,$post)=@_;require_admin($p);fail(405,'Use POST to publish a document.') unless $post;
    my $key=text($b->{document_key},80);fail(400,'Unknown document.') unless $key=~/\A(?:terms|waiver|help)\z/;
    my $version=text($b->{version},40);my $body=text($b->{body},100000);my $title=text($b->{title},200);
    fail(400,'Title, version and body are required.') unless length($version) && length($body) && length($title);
    my $old=one('SELECT * FROM '.t('documents').' WHERE document_key=?',$key);
    my $historic=one('SELECT * FROM '.t('document_versions').' WHERE document_key=? AND version=?',$key,$version);
    fail(409,'This version already exists. Use a new version identifier.') if $historic && ($historic->{body} ne $body || $historic->{title} ne $title);
    fail(409,'Publish a new version when changing an existing agreement.') if $old && $old->{version} eq $version && ($old->{body} ne $body || $old->{title} ne $title);
    db()->do('INSERT INTO '.t('documents').' (document_key,version,title,body,required) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE version=VALUES(version),title=VALUES(title),body=VALUES(body),required=VALUES(required)',undef,$key,$version,$title,$body,$b->{required}?1:0);
    db()->do('INSERT IGNORE INTO '.t('document_versions').' (document_key,version,title,body) VALUES (?,?,?,?)',undef,$key,$version,$title,$body);
    audit($p,'document',$key,"Published $version");return {saved=>1};
}
sub agreements {
    my ($c,$p,$b,$post)=@_;require_user($p);
    if ($post) {
        fail(400,'Choose agreement versions to accept.') unless ref($b->{versions}) eq 'HASH' && keys %{$b->{versions}};
        for my $key (keys %{$b->{versions}}) {
            my $doc=one('SELECT * FROM '.t('documents').' WHERE document_key=?',$key);
            fail(409,'Agreement changed; reload and read the current version.') unless $doc && $doc->{version} eq $b->{versions}{$key};
        }
        for my $key (keys %{$b->{versions}}) {db()->do('INSERT IGNORE INTO '.t('legal_acceptances').' (borrowernumber,document_key,document_version) VALUES (?,?,?)',undef,$p->borrowernumber,$key,$b->{versions}{$key})}
    }
    return {documents=>rows('SELECT * FROM '.t('documents')),acceptances=>rows('SELECT * FROM '.t('legal_acceptances').' WHERE borrowernumber=? ORDER BY accepted_at DESC',$p->borrowernumber),pending=>pending($p->borrowernumber)};
}
sub profile {
    my ($c,$p,$b,$post)=@_;require_user($p);
    my $pid=$post?$p->borrowernumber:id($c->param('patron_id')//$p->borrowernumber);
    if ($post) {db()->do('INSERT INTO '.t('preferences').' (borrowernumber,show_in_leaderboard) VALUES (?,?) ON DUPLICATE KEY UPDATE show_in_leaderboard=VALUES(show_in_leaderboard)',undef,$pid,$b->{show_in_leaderboard}?1:0)}
    my $patron=one('SELECT borrowernumber,firstname,surname FROM borrowers WHERE borrowernumber=?',$pid);
    fail(404,'Library member not found.') unless $patron;
    my $stats=Koha::Plugin::Com::LibraryShare::Stats::recompute($pid);
    my $defs=rows('SELECT * FROM '.t('badge_definitions').' WHERE active=1');
    for (@$defs) {$_->{progress}=$stats->{$_->{metric}}//0}
    return {patron=>$patron,stats=>$stats,levels=>Koha::Plugin::Com::LibraryShare::Stats::levels($stats),goals=>$defs,
      badges=>rows('SELECT * FROM '.t('badges').' WHERE borrowernumber=? ORDER BY earned_at DESC',$pid),
      reviews=>rows('SELECT v.*,b.firstname,b.surname FROM '.t('reviews').' v JOIN borrowers b ON b.borrowernumber=v.reviewer_borrowernumber WHERE v.reviewee_borrowernumber=? ORDER BY v.created_at DESC',$pid),
      kudos=>rows('SELECT k.*,b.firstname,b.surname FROM '.t('kudos').' k JOIN borrowers b ON b.borrowernumber=k.sender_borrowernumber WHERE k.recipient_borrowernumber=? ORDER BY k.created_at DESC',$pid),
      listings=>rows('SELECT id,title,category,description,status,estimated_value FROM '.t('listings').' WHERE owner_borrowernumber=? AND status="active"',$pid),
      ledger=>$pid==$p->borrowernumber?rows('SELECT * FROM '.t('share_credits_ledger').' WHERE patron_borrowernumber=? ORDER BY id DESC LIMIT 500',$pid):[],
      preferences=>one('SELECT show_in_leaderboard FROM '.t('preferences').' WHERE borrowernumber=?',$pid)//{show_in_leaderboard=>1},is_self=>$pid==$p->borrowernumber?1:0};
}
sub facets {return {categories=>rows('SELECT category,COUNT(*) AS count FROM '.t('listings').' WHERE status="active" GROUP BY category ORDER BY category'),branches=>rows('SELECT branchcode,branchname FROM branches ORDER BY branchname')}}
sub availability {
    my ($c)=@_;my $listing=id($c->param('listing_id'));
    require Koha::Plugin::Com::LibraryShare::PickupAvailability;
    my $slots=rows('SELECT id,starts_at,ends_at,branchcode,location,status FROM '.t('pickup_slots').' WHERE listing_id=? AND starts_at>NOW() AND status="open" ORDER BY starts_at',$listing);
    my $open=eval {Koha::Plugin::Com::LibraryShare::PickupAvailability::filter_open(db(),$slots)};
    fail(400,Koha::Plugin::Com::LibraryShare::PickupAvailability::public_error($@)) unless $open;
    return {slots=>$open,
      loans=>rows('SELECT s.starts_at,r.due_date AS ends_at,r.status FROM '.t('borrow_requests').' r LEFT JOIN '.t('pickup_slots').' s ON s.id=r.pickup_slot_id WHERE r.listing_id=? AND r.status="approved"',$listing),events=>[]};
}
sub participant {
    my ($p,$rid)=@_;require_user($p);
    my $r=one('SELECT * FROM '.t('borrow_requests').' WHERE id=?',id($rid));
    fail(404,'Request not found.') unless $r;
    fail(403,'Only request participants can view this.') unless $p->borrowernumber==$r->{borrower_borrowernumber} || $p->borrowernumber==$r->{owner_borrowernumber};
    return $r;
}
sub history {
    my ($c,$p)=@_;my $r=participant($p,$c->param('request_id'));
    return {events=>rows('SELECT * FROM '.t('handoff_events').' WHERE request_id=? ORDER BY created_at,id',$r->{id})};
}
sub matches {
    my ($c,$p)=@_;require_user($p);
    return {matches=>rows('SELECT w.id AS wanted_id,w.title AS wanted_title,l.id AS listing_id,l.title,l.category FROM '.t('wanted_items').' w JOIN '.t('listings').' l ON (l.category=w.category OR l.title LIKE CONCAT("%",w.title,"%")) WHERE w.patron_borrowernumber=? AND w.status="open" AND l.status="active" AND l.owner_borrowernumber<>? ORDER BY l.created_at DESC LIMIT 100',$p->borrowernumber,$p->borrowernumber)};
}
sub fulfil {
    my ($c,$p,$b,$post)=@_;require_user($p);fail(405,'Use POST.') unless $post;
    my $w=one('SELECT * FROM '.t('wanted_items').' WHERE id=?',id($b->{wanted_id}));fail(404,'Wanted post not found.') unless $w;
    if (exists $b->{status}) {
        fail(403,'Only the requester can change this status.') unless $w->{patron_borrowernumber}==$p->borrowernumber;
        fail(400,'Unknown status.') unless $b->{status}=~/\A(?:open|closed|fulfilled)\z/;
        db()->do('UPDATE '.t('wanted_items').' SET status=? WHERE id=?',undef,$b->{status},$w->{id});
    } else {
        my $l=one('SELECT * FROM '.t('listings').' WHERE id=? AND status="active"',id($b->{listing_id}));
        fail(403,'Choose an active listing you own.') unless $l && $l->{owner_borrowernumber}==$p->borrowernumber;
        fail(409,'This post is not open.') unless $w->{status} eq 'open';
        db()->do('INSERT INTO '.t('fulfilments').' (wanted_id,listing_id,lender) VALUES (?,?,?)',undef,$w->{id},$l->{id},$p->borrowernumber);
        db()->do('UPDATE '.t('wanted_items').' SET status="fulfilled" WHERE id=?',undef,$w->{id});
        Koha::Plugin::Com::LibraryShare::Controller::API::_notify(db(),$w->{patron_borrowernumber},'wish_match','A member listed your wanted item',$l->{title},'/api/v1/contrib/libraryshare/static/app.html','wish:'.$w->{id});
        Koha::Plugin::Com::LibraryShare::Stats::recompute($p->borrowernumber);
    }
    return {saved=>1};
}
sub reports {
    my ($c,$p,$b,$post)=@_;require_user($p);
    if (!$post) {require_admin($p);return {reports=>rows('SELECT * FROM '.t('reports').' ORDER BY created_at DESC')}}
    if ($b->{id}) {
        require_admin($p);my $status=$b->{status}//'';fail(400,'Unknown report status.') unless $status=~/\A(?:resolved|dismissed)\z/;
        db()->do('UPDATE '.t('reports').' SET status=?,resolution=? WHERE id=?',undef,$status,text($b->{note},2000),id($b->{id}));audit($p,'report',$b->{id},$b->{note});
    } else {
        my $lid=id($b->{listing_id});my $reason=text($b->{reason},2000);fail(400,'A report reason is required.') unless $reason=~/\S/;
        fail(404,'Listing not found.') unless one('SELECT id FROM '.t('listings').' WHERE id=?',$lid);
        db()->do('INSERT INTO '.t('reports').' (listing_id,reporter_borrowernumber,reason) VALUES (?,?,?)',undef,$lid,$p->borrowernumber,$reason);
    }
    return {saved=>1};
}
sub notifications {
    my ($c,$p,$b,$post)=@_;require_user($p);fail(400,'Choose notification IDs.') unless $post && ref($b->{ids}) eq 'ARRAY' && @{$b->{ids}}<=100;
    fail(400,'Unknown notification action.') unless ($b->{action}//'')=~/\A(?:read|dismiss)\z/;
    for my $nid (@{$b->{ids}}) {
        my $sql=$b->{action} eq 'read'?'UPDATE '.t('notifications').' SET read_at=NOW()':'DELETE FROM '.t('notifications');
        db()->do($sql.' WHERE id=? AND patron_borrowernumber=?',undef,id($nid),$p->borrowernumber);
    }
    return {saved=>1};
}
sub impact {
    my ($c,$p,$b,$post)=@_;
    fail(405,'Category impact editing has been retired. Edit the estimated value on the item listing instead.') if $post;
    my $join=' FROM '.t('borrow_requests').' r JOIN '.t('listings').' l ON l.id=r.listing_id WHERE r.status="returned"';
    my $featured;
    my $fid=Koha::Plugin::Com::LibraryShare::Stats::setting('featured_lender',0);
    if (!$fid) {my $r=one('SELECT s.borrowernumber FROM '.t('patron_stats').' s LEFT JOIN '.t('preferences').' p ON p.borrowernumber=s.borrowernumber WHERE COALESCE(p.show_in_leaderboard,1)=1 ORDER BY s.loans_as_lender DESC LIMIT 1');$fid=$r?$r->{borrowernumber}:0}
    if ($fid) {
        my $public=one('SELECT b.borrowernumber,b.firstname,b.surname FROM borrowers b LEFT JOIN '.t('preferences').' p ON p.borrowernumber=b.borrowernumber WHERE b.borrowernumber=? AND COALESCE(p.show_in_leaderboard,1)=1',$fid);
        $featured={patron=>$public,stats=>Koha::Plugin::Com::LibraryShare::Stats::recompute($fid),kudos=>rows('SELECT message,created_at FROM '.t('kudos').' WHERE recipient_borrowernumber=? ORDER BY created_at DESC LIMIT 10',$fid)} if $public;
    }
    return {totals=>one('SELECT COUNT(*) AS loans,COALESCE(SUM(ROUND(l.estimated_value/2,2)),0) AS value_saved,COUNT(*)-COUNT(l.estimated_value) AS unvalued_loans'.$join),
      monthly=>rows('SELECT DATE_FORMAT(r.returned_at,"%Y-%m") AS month,COUNT(*) AS loans'.$join.' GROUP BY month ORDER BY month'),
      categories=>rows('SELECT l.category,COUNT(*) AS loans,COALESCE(SUM(ROUND(l.estimated_value/2,2)),0) AS value_saved,COUNT(*)-COUNT(l.estimated_value) AS unvalued_loans'.$join.' GROUP BY l.category'),
      branches=>rows('SELECT l.pickup_branch AS branchcode,COUNT(*) AS loans'.$join.' GROUP BY l.pickup_branch'),
      featured=>$featured,community_goal=>settings()->{community_goal},milestone_loans=>settings()->{milestone_loans}};
}
sub credits {
    my ($c,$p,$b,$post)=@_;require_user($p);
    if ($post) {
        require_admin($p);
        if ($b->{recompute}) {
            Koha::Plugin::Com::LibraryShare::Stats::reconcile();
            audit($p,'recompute','all','Recomputed derived statistics');
        } else {
            my $pid=id($b->{patron_id});my $delta=$b->{delta};my $note=text($b->{note},500);
            fail(400,'A signed integer adjustment and explanation are required.') unless defined($delta) && "$delta"=~/\A-?\d+\z/ && abs($delta)<=100000 && $note=~/\S/;
            fail(404,'Patron not found.') unless one('SELECT borrowernumber FROM borrowers WHERE borrowernumber=?',$pid);
            db()->do('INSERT INTO '.t('share_credits_ledger').' (patron_borrowernumber,delta,reason,note) VALUES (?,?,"admin_adjust",?)',undef,$pid,$delta,$note);audit($p,'credits',$pid,$note);
            Koha::Plugin::Com::LibraryShare::Stats::recompute($pid);
        }
    }
    my $m=Koha::Plugin::Com::LibraryShare::Stats::recompute($p->borrowernumber);
    return {balance=>$m->{share_credits},ledger=>rows('SELECT * FROM '.t('share_credits_ledger').' WHERE patron_borrowernumber=? ORDER BY id DESC LIMIT 500',$p->borrowernumber),settings=>settings()};
}
sub badges {
    my ($c,$p,$b,$post)=@_;
    if ($post) {
        require_admin($p);my $slug=text($b->{slug},80);fail(400,'Badge slug must contain letters, digits, underscores or hyphens.') unless $slug=~/\A[a-z0-9_-]+\z/;
        if ($b->{remove}) {db()->do('UPDATE '.t('badge_definitions').' SET active=0 WHERE slug=?',undef,$slug)}
        else {
            my %metrics=map {$_=>1} qw(loans_as_lender loans_as_borrower distinct_items_lent distinct_categories_lent kudos_count streak_months_lender avg_rating_lender on_time_returns perfect_streak category_specialist longest_loan_days community_pillar careful_custodian wishes_fulfilled distinct_categories_borrowed);
            fail(400,'Invalid badge metric or threshold.') unless $metrics{$b->{metric}//''} && defined($b->{threshold}) && "$b->{threshold}"=~/\A\d+(?:\.\d+)?\z/;
            db()->do('INSERT INTO '.t('badge_definitions').' (slug,label,description,family,metric,threshold,active) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE label=VALUES(label),description=VALUES(description),family=VALUES(family),metric=VALUES(metric),threshold=VALUES(threshold),active=VALUES(active)',undef,$slug,text($b->{label},200),text($b->{description},1000),text($b->{family}//'community',20),$b->{metric},$b->{threshold},$b->{active}?1:0);
        }
        audit($p,'badge',$slug,'Updated badge definition');
    }
    return {badges=>rows('SELECT * FROM '.t('badge_definitions').' ORDER BY family,threshold'),levels=>[{slug=>'newcomer',loans=>0,min_rating=>0},{slug=>'contributor',loans=>3,min_rating=>4},{slug=>'steward',loans=>10,min_rating=>4.3},{slug=>'champion',loans=>25,min_rating=>4.5},{slug=>'pillar',loans=>60,min_rating=>4.7}]};
}
sub challenges {
    my ($c,$p,$b,$post)=@_;
    if ($post) {
        require_admin($p);
        if ($b->{remove}) {db()->do('UPDATE '.t('challenges').' SET active=0 WHERE id=?',undef,id($b->{id}))}
        else {
            my $goal=id($b->{goal});
            fail(400,'Valid ordered dates are required.') unless ($b->{start_date}//'')=~/\A\d{4}-\d\d-\d\d\z/ && ($b->{end_date}//'')=~/\A\d{4}-\d\d-\d\d\z/ && $b->{end_date} ge $b->{start_date};
            my @v=(text($b->{title},200),text($b->{description},1000),$goal,$b->{start_date},$b->{end_date},$b->{active}?1:0);
            if ($b->{id}) {db()->do('UPDATE '.t('challenges').' SET title=?,description=?,goal=?,start_date=?,end_date=?,active=? WHERE id=?',undef,@v,id($b->{id}))}
            else {db()->do('INSERT INTO '.t('challenges').' (title,description,goal,start_date,end_date,active) VALUES (?,?,?,?,?,?)',undef,@v)}
        }
        audit($p,'challenge',$b->{id}//'new','Updated challenge');
    }
    return {challenges=>rows('SELECT c.*,COALESCE(p.progress,0) AS progress FROM '.t('challenges').' c LEFT JOIN '.t('challenge_progress').' p ON p.challenge_id=c.id AND p.borrowernumber=? ORDER BY c.end_date DESC',$p?$p->borrowernumber:0)};
}
sub diagnostics {
    my ($c,$p)=@_;require_admin($p);
    require Koha::Plugin::Com::LibraryShare::Media;
    my $path=Koha::Plugin::Com::LibraryShare::Media::directory(0);
    my $code=settings()->{item_type_code};
    return {database=>'ok',item_type=>{code=>$code,exists=>one('SELECT itemtype FROM itemtypes WHERE itemtype=?',$code)?1:0},
      media=>{configured=>$path?1:0,writable=>$path && -w $path?1:0},koha_version=>C4::Context->preference('Version'),route_namespace=>'/api/v1/contrib/libraryshare'};
}
sub administration {
    require Koha::Plugin::Com::LibraryShare::Administration;
    return Koha::Plugin::Com::LibraryShare::Administration::handle(@_);
}
sub photos {
    require Koha::Plugin::Com::LibraryShare::Media;
    return Koha::Plugin::Com::LibraryShare::Media::handle(@_);
}
sub media {
    require Koha::Plugin::Com::LibraryShare::Media;
    return Koha::Plugin::Com::LibraryShare::Media::serve(@_);
}
1;
