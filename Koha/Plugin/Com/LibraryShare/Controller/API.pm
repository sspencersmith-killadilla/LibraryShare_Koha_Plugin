package Koha::Plugin::Com::LibraryShare::Controller::API;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use C4::Context;
use JSON qw(decode_json encode_json);
use POSIX ();
use Scalar::Util qw(blessed);
use Try::Tiny qw(try catch);
use Koha::Plugin::Com::LibraryShare::Stats;
use Koha::Plugin::Com::LibraryShare::Value;

sub _dbh { return C4::Context->dbh; }

sub _patron {
    my ($c) = @_;
    my $user = $c->stash('koha.user');
    return unless $user && blessed($user) && $user->can('borrowernumber');
    return $user;
}

sub _json_body {
    my ($c) = @_;
    my $body = $c->req->json;
    return ref($body) eq 'HASH' ? $body : {};
}

sub _error {
    my ( $c, $status, $message ) = @_;
    return $c->render( status => $status, json => { error => $message } );
}

sub _need_patron {
    my ($c) = @_;
    if ($c->req->method ne 'GET' && ($c->req->headers->content_type//'') !~ m{\Aapplication/json\b}i) {
        _error($c,415,'Send mutations as application/json.');return;
    }
    my $patron = _patron($c);
    return $patron if $patron;
    _error( $c, 401, 'Sign in to your Koha account to use LibraryShare.' );
    return;
}

sub _plugin_table {
    my ($name) = @_;
    die 'Invalid table name' unless $name =~ /\A[a-z_]+\z/;
    return 'koha_plugin_com_libraryshare_' . $name;
}

# Shared inventory eligibility: independent of patron credits and listing age.
sub _available_sql {
    return 'l.status = ? AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.itemnumber = l.itemnumber)';
}

sub bootstrap {
    my ($c) = @_;
    require Koha::Plugin::Com::LibraryShare::Navigation;
    my $patron = _patron($c);
    my $dbh = _dbh();
    my ($items) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM ' . _plugin_table('listings') . ' l WHERE ' . _available_sql(),
        undef, 'active'
    );
    my ($loans) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM ' . _plugin_table('borrow_requests') . ' WHERE status = ?',
        undef, 'returned'
    );
    my $branches = $dbh->selectall_arrayref(
        'SELECT branchcode, branchname FROM branches ORDER BY branchname',
        { Slice => {} }
    );
    return $c->render(
        status => 200,
        json => {
            signed_in => $patron ? 1 : 0,
            navigation => Koha::Plugin::Com::LibraryShare::Navigation::links($c),
            patron => $patron ? {
                borrowernumber => 0 + $patron->borrowernumber,
                firstname => $patron->firstname // '',
                surname => $patron->surname // '',
            } : undef,
            community => { listings => 0 + ($items || 0), loans_completed => 0 + ($loans || 0) },
            default_loan_days => 0 + _setting( $dbh, 'default_loan_days', 14 ),
            branches => $branches || [],
            features => [qw(listings requests pickup_scheduler messages wanted reviews notifications impact badges challenges admin)],
        }
    );
}

sub listings {
    my ($c) = @_;
    my $dbh = _dbh();
    my $patron = _patron($c);
    my $viewer = $patron ? $patron->borrowernumber : 0;
    my $search = $c->param('q') // '';
    my $sql = 'SELECT l.id, l.estimated_value, l.owner_borrowernumber, (SELECT CONCAT("/api/v1/contrib/libraryshare/media/",MIN(ph.id)) FROM '._plugin_table('photos').' ph WHERE ph.listing_id=l.id) AS photo_url, (l.owner_borrowernumber = ?) AS is_mine, l.title, l.author, l.category, l.description, l.item_condition, l.pickup_branch, l.pickup_location, l.default_loan_days, l.status, l.created_at, b.firstname, b.surname FROM '
        . _plugin_table('listings')
        . ' l LEFT JOIN borrowers b ON b.borrowernumber = l.owner_borrowernumber WHERE ' . _available_sql();
    my @bind = ($viewer, 'active');
    if (my $location=$c->param('location')) {$sql.=' AND l.pickup_location LIKE ?';push @bind,'%'.$location.'%'}
    my ($from,$to)=($c->param('available_from'),$c->param('available_to'));
    if ($from || $to) {
        $from//=$to;$to//=$from;
        return _error($c,400,'Use ordered ISO availability dates.') unless $from=~/\A\d{4}-\d\d-\d\d\z/ && $to=~/\A\d{4}-\d\d-\d\d\z/ && $from le $to;
        $sql.=' AND NOT EXISTS (SELECT 1 FROM '._plugin_table('borrow_requests').' ar JOIN '._plugin_table('pickup_slots').' aps ON aps.id=ar.pickup_slot_id WHERE ar.listing_id=l.id AND ar.status="approved" AND DATE(aps.starts_at)<=? AND DATE(ar.due_date)>=?)';
        push @bind,$to,$from;
    }
    for my $filter (['category','category'],['branch','pickup_branch'],['condition','item_condition']) {
        my $value=$c->param($filter->[0]);
        if (defined($value) && length($value)) {$sql.=' AND l.'.$filter->[1].' = ?';push @bind,$value}
    }
    if ( length $search ) {
        $sql .= ' AND (l.title LIKE ? OR l.author LIKE ? OR l.category LIKE ?)';
        my $pattern = '%' . $search . '%';
        push @bind, $pattern, $pattern, $pattern;
    }
    $sql .= ' ORDER BY l.created_at DESC LIMIT 100';
    my $rows = $dbh->selectall_arrayref( $sql, { Slice => {} }, @bind );
    my ($total)=$dbh->selectrow_array(
        'SELECT COUNT(*) FROM '._plugin_table('listings').' l WHERE '._available_sql(),
        undef,'active');
    return $c->render( status => 200, json => { listings => $rows, total_available=>0+($total||0) } );
}

sub listing_detail {
    my ($c) = @_;
    my $id = $c->stash('listing_id') // '';
    return _error( $c, 400, 'Invalid listing id.' ) unless $id =~ /\A\d+\z/;
    my $row = _dbh()->selectrow_hashref(
        'SELECT l.*, b.firstname, b.surname FROM ' . _plugin_table('listings')
        . ' l LEFT JOIN borrowers b ON b.borrowernumber = l.owner_borrowernumber WHERE l.id = ? AND l.status != ?',
        undef, $id, 'removed'
    );
    return _error( $c, 404, 'Listing not found.' ) unless $row;
    my $viewer=_patron($c);
    unless ($viewer && $viewer->borrowernumber == $row->{owner_borrowernumber}) {
        my ($available)=_dbh()->selectrow_array(
            'SELECT COUNT(*) FROM '._plugin_table('listings').' l WHERE l.id = ? AND '._available_sql(),
            undef,$id,'active');
        return _error($c,404,'This item is not currently available.') unless $available;
    }
    return $c->render( status => 200, json => { listing => $row } );
}

sub update_listing {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $id = $c->stash('listing_id') // '';
    return _error( $c, 400, 'Invalid listing id.' ) unless $id =~ /\A\d+\z/;
    my $dbh = _dbh();
    my $listing = $dbh->selectrow_hashref(
        'SELECT * FROM ' . _plugin_table('listings') . ' WHERE id = ?',
        undef, $id
    );
    return _error( $c, 404, 'Listing not found.' ) unless $listing;
    return _error( $c, 403, 'Only the owner can update this listing.' )
        unless $listing->{owner_borrowernumber} == $patron->borrowernumber;
    my $body = _json_body($c);
    if ( exists $body->{status} ) {
        return _error( $c, 400, 'Status must be active, paused, or removed.' )
            unless $body->{status} =~ /\A(?:active|paused|removed)\z/;
        my $on_loan = $dbh->selectrow_array(
            'SELECT issue_id FROM issues WHERE itemnumber = ? LIMIT 1',
            undef, $listing->{itemnumber}
        );
        return _error( $c, 409, 'Return the Koha checkout before changing this listing.' ) if $on_loan;
        $dbh->do(
            'UPDATE ' . _plugin_table('listings') . ' SET status = ? WHERE id = ?',
            undef, $body->{status}, $id
        );
        return $c->render( status => 200, json => { id => 0 + $id, status => $body->{status} } );
    }
    my %allowed = (
        title => 200,
        author => 200,
        category => 80,
        description => 4000,
        item_condition => 40,
        pickup_branch => 10,
        pickup_location => 200,
    );
    my ( @set, @bind );
    if (exists $body->{estimated_value}) {
        my $value=eval {Koha::Plugin::Com::LibraryShare::Value::validate($body->{estimated_value})};
        return _error($c,400,"$@") if $@;
        push @set,'estimated_value = ?';
        push @bind,$value;
    }
    for my $field ( sort keys %allowed ) {
        next unless exists $body->{$field};
        my $value = defined $body->{$field} ? substr( $body->{$field}, 0, $allowed{$field} ) : '';
        push @set, "$field = ?";
        push @bind, $value;
    }
    if ( exists $body->{default_loan_days} ) {
        my $days = $body->{default_loan_days};
        return _error( $c, 400, 'Loan length must be between 1 and 90 days.' )
            unless $days =~ /\A\d+\z/ && $days >= 1 && $days <= 90;
        push @set, 'default_loan_days = ?';
        push @bind, $days;
    }
    return _error( $c, 400, 'No supported listing fields were provided.' ) unless @set;
    return _error($c,400,'A listing title cannot be blank.') if exists($body->{title}) && $body->{title}!~/\S/;
    if (exists $body->{pickup_branch}) {
        return _error($c,400,'Choose an existing library branch.') unless $dbh->selectrow_array('SELECT branchcode FROM branches WHERE branchcode=?',undef,$body->{pickup_branch});
    }
    push @bind, $id;
    my $error;
    try {
    require Koha::Database;
    Koha::Database->new->schema->txn_do(sub {
        require Koha::Biblios;
        require Koha::Items;
        require C4::Biblio;
        require MARC::Field;
        if (exists($body->{title}) || exists($body->{author})) {
            my $bib=Koha::Biblios->find($listing->{biblionumber}) or die 'Bibliographic record missing';
            my $record=$bib->metadata->record;
            for my $pair (['title','biblio.title'],['author','biblio.author']) {
                next unless exists $body->{$pair->[0]};
                my ($tag,$sub)=C4::Biblio::GetMarcFromKohaField($pair->[1],$bib->frameworkcode);
                die 'Missing MARC mapping' unless $tag && $sub;
                my $field=$record->field($tag);
                if ($field) {$field->update($sub=>substr($body->{$pair->[0]},0,200))}
                else {$record->append_fields(MARC::Field->new($tag,' ',' ',$sub=>substr($body->{$pair->[0]},0,200)))}
            }
            C4::Biblio::ModBiblio($record,$listing->{biblionumber},$bib->frameworkcode);
        }
        if (exists $body->{pickup_branch}) {
            my $item=Koha::Items->find($listing->{itemnumber}) or die 'Item missing';
            die 'Return the item before changing its branch' if $item->checkout;
            $item->homebranch($body->{pickup_branch});$item->holdingbranch($body->{pickup_branch});$item->store;
        }
    $dbh->do(
        'UPDATE ' . _plugin_table('listings') . ' SET ' . join( ', ', @set ) . ' WHERE id = ?',
        undef, @bind
    );
    Koha::Plugin::Com::LibraryShare::Value::refresh($dbh,$patron->borrowernumber) if exists $body->{estimated_value};
    });
    } catch {$error=$_;$c->app->log->error("LibraryShare edit: $_")};
    return _error($c,409,'The Koha record could not be updated. Check whether the item is checked out and ask staff to check its catalog mapping.') if $error;
    return $c->render( status => 200, json => { saved => 1 } );
}

sub create_listing {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    return unless _agreements_ok($c,$patron);
    my $body = _json_body($c);
    for my $required (qw(title category)) {
        return _error( $c, 400, "Missing required field: $required" )
            unless defined $body->{$required} && $body->{$required} =~ /\S/;
    }
    return _error( $c, 400, 'Title must be 200 characters or fewer.' ) if length($body->{title}) > 200;
    return _error( $c, 400, 'Category must be 80 characters or fewer.' ) if length($body->{category}) > 80;
    my $value=eval {Koha::Plugin::Com::LibraryShare::Value::validate($body->{estimated_value})};
    return _error($c,400,"$@") if $@;
    my $days = $body->{default_loan_days} // _setting( _dbh(), 'default_loan_days', 14 );
    return _error( $c, 400, 'Loan length must be between 1 and 90 days.' )
        unless $days =~ /\A\d+\z/ && $days >= 1 && $days <= 90;

    my $branch = $body->{pickup_branch} || $patron->branchcode;
    return _error( $c, 400, 'Choose a Koha branch for pickup.' ) unless $branch;
    my $dbh = _dbh();
    my $biblionumber;
    my $itemnumber;
    my $listing_id;
    my $error;
    try {
        require Koha::Database;
        Koha::Database->new->schema->txn_do(sub {
        require C4::Biblio;
        require Koha::Item;
        require MARC::Record;
        require MARC::Field;
        my $record = MARC::Record->new;
        $record->leader('     nam a22     4500');
        $record->append_fields( MARC::Field->new( '245', '0', '0', a => $body->{title} ) );
        my $item_type = _setting( $dbh, 'item_type_code', C4::Context->preference('LibraryShareItemType') || 'PEERLEND' );
        $record->append_fields( MARC::Field->new( '942', '0', '0', c => $item_type ) );
        if ( $body->{author} && $body->{author} =~ /\S/ ) {
            $record->append_fields( MARC::Field->new( '100', '1', ' ', a => $body->{author} ) );
        }
        my ( $bib_id, $bibitem_id ) = C4::Biblio::AddBiblio( $record, '' );
        die 'Koha could not create a bibliographic record for this item.' unless $bib_id;
        $biblionumber = $bib_id;
        my $barcode = 'LS-' . $patron->borrowernumber . '-' . time . '-' . int(rand(10000));
        my $item = Koha::Item->new({
            biblionumber => $bib_id,
            biblioitemnumber => $bibitem_id,
            homebranch => $branch,
            holdingbranch => $branch,
            itype => $item_type,
            barcode => $barcode,
            notforloan => 0,
            itemnotes_nonpublic => 'LibraryShare patron-owned item',
        })->store;
        die 'Koha could not create the circulation item.' unless $item;
        $itemnumber = $item->itemnumber;
        $dbh->do(
            'INSERT INTO ' . _plugin_table('listings')
            . ' (owner_borrowernumber, title, author, category, description, item_condition, pickup_branch, pickup_location, default_loan_days, biblionumber, itemnumber, status, estimated_value) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            undef,
            $patron->borrowernumber, $body->{title}, $body->{author} // '', $body->{category},
            $body->{description} // '', $body->{condition} // 'good', $branch,
            $body->{pickup_location} // '', $days, $bib_id, $itemnumber, 'active', $value
        );
        ($listing_id) = $dbh->selectrow_array('SELECT LAST_INSERT_ID()');
        });
        1;
    }
    catch {
        $error = $_;
    };
    return _error( $c, 500, 'The item could not be added to Koha. Check the configured peer-lending item type and branch.' )
        if $error || !$listing_id;
    return $c->render( status => 201, json => { id => 0 + $listing_id, biblionumber => 0 + $biblionumber, itemnumber => 0 + $itemnumber } );
}

sub dashboard {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $dbh = _dbh();
    Koha::Plugin::Com::LibraryShare::Stats::recompute($patron->borrowernumber);
    my $requests = $dbh->selectall_arrayref(
        'SELECT r.*, l.title, l.author, l.default_loan_days AS listing_default_loan_days, p.starts_at AS pickup_starts_at, p.location AS pickup_location, lender.firstname AS lender_firstname, lender.surname AS lender_surname, borrower.firstname AS borrower_firstname, borrower.surname AS borrower_surname FROM '
        . _plugin_table('borrow_requests')
        . ' r JOIN ' . _plugin_table('listings') . ' l ON l.id = r.listing_id'
        . ' LEFT JOIN borrowers lender ON lender.borrowernumber = r.owner_borrowernumber'
        . ' LEFT JOIN borrowers borrower ON borrower.borrowernumber = r.borrower_borrowernumber'
        . ' LEFT JOIN ' . _plugin_table('pickup_slots') . ' p ON p.id = r.pickup_slot_id'
        . ' WHERE r.borrower_borrowernumber = ? OR l.owner_borrowernumber = ? ORDER BY r.created_at DESC LIMIT 100',
        { Slice => {} }, $patron->borrowernumber, $patron->borrowernumber
    );
    for my $r (@$requests) {
        my $window=$dbh->selectrow_hashref('SELECT proposed_start,proposed_end FROM '._plugin_table('loan_windows').' WHERE request_id=?',undef,$r->{id})//{};
        @$r{qw(proposed_start proposed_end)}=@$window{qw(proposed_start proposed_end)};
        my $s=Koha::Plugin::Com::LibraryShare::Stats::recompute($r->{borrower_borrowernumber});
        $r->{borrower_priority}=_setting($dbh,'gamification_enabled',1) && $s->{share_credits}>=_setting($dbh,'priority_threshold',30)?1:0;
        $r->{borrower_fast_track}=_setting($dbh,'gamification_enabled',1) && $s->{on_time_returns}>=_setting($dbh,'fast_track_min_on_time',3)?1:0;
    }
    @$requests=sort {$b->{borrower_priority}<=>$a->{borrower_priority} || $b->{id}<=>$a->{id}} @$requests;
    my $mine = $dbh->selectall_arrayref(
        'SELECT id, title, author, category, status, created_at FROM ' . _plugin_table('listings')
        . ' WHERE owner_borrowernumber = ? ORDER BY created_at DESC',
        { Slice => {} }, $patron->borrowernumber
    );
    my $wanted = $dbh->selectall_arrayref(
        'SELECT id, title, category, description, status, created_at FROM ' . _plugin_table('wanted_items')
        . ' WHERE patron_borrowernumber = ? ORDER BY created_at DESC',
        { Slice => {} }, $patron->borrowernumber
    );
    my $stats = $dbh->selectrow_hashref(
        'SELECT loans_as_lender, loans_as_borrower, distinct_items_lent, est_value_saved, level, share_credits FROM '
        . _plugin_table('patron_stats') . ' WHERE borrowernumber = ?',
        undef, $patron->borrowernumber
    ) || {};
    return $c->render( status => 200, json => { requests => $requests, listings => $mine, wanted => $wanted, stats => $stats } );
}

sub create_request {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    return unless _agreements_ok($c,$patron);
    my $body = _json_body($c);
    for my $key (qw(proposed_start proposed_end)) {
        return _error($c,400,'Use ISO dates for the requested loan period.') if $body->{$key} && $body->{$key}!~/\A\d{4}-\d\d-\d\d\z/;
    }
    return _error($c,400,'Requested end date must follow the start date.') if $body->{proposed_start} && $body->{proposed_end} && $body->{proposed_end} lt $body->{proposed_start};
    return _error( $c, 400, 'Choose an item to request.' ) unless $body->{listing_id} && $body->{listing_id} =~ /\A\d+\z/;
    my $dbh = _dbh();
    my $listing = $dbh->selectrow_hashref(
        'SELECT l.* FROM ' . _plugin_table('listings') . ' l WHERE l.id = ? AND ' . _available_sql(),
        undef, $body->{listing_id}, 'active'
    );
    return _error( $c, 404, 'This item is no longer available.' ) unless $listing;
    return _error( $c, 400, 'You cannot request your own item.' )
        if $listing->{owner_borrowernumber} == $patron->borrowernumber;
    my $overdue = _has_overdues( $patron->borrowernumber );
    return _error( $c, 403, 'Your Koha account has overdue items or a circulation restriction.' ) if $overdue;
    my $exists = $dbh->selectrow_array(
        'SELECT id FROM ' . _plugin_table('borrow_requests')
        . ' WHERE listing_id = ? AND borrower_borrowernumber = ? AND status IN (?, ?, ?)',
        undef, $listing->{id}, $patron->borrowernumber, 'pending', 'accepted', 'approved'
    );
    return _error( $c, 409, 'You already have an active request for this item.' ) if $exists;
    $dbh->do(
        'INSERT INTO ' . _plugin_table('borrow_requests')
        . ' (listing_id, owner_borrowernumber, borrower_borrowernumber, status, borrower_message) VALUES (?, ?, ?, ?, ?)',
        undef, $listing->{id}, $listing->{owner_borrowernumber}, $patron->borrowernumber,
        'pending', substr( $body->{message} // '', 0, 1000 )
    );
    my ($id) = $dbh->selectrow_array('SELECT LAST_INSERT_ID()');
    $dbh->do('INSERT INTO '._plugin_table('loan_windows').' (request_id,proposed_start,proposed_end) VALUES (?,?,?)',undef,$id,$body->{proposed_start}||undef,$body->{proposed_end}||undef);
        _notify(
            $dbh, $listing->{owner_borrowernumber}, 'request_received',
            'A member requested your item', $listing->{title}, '/cgi-bin/koha/opac-main.pl',
            'request_received:' . $id
        );
    return $c->render( status => 201, json => { id => 0 + $id, status => 'pending' } );
}

sub request_action {
    my ($c)=@_;
    my $id=$c->stash('request_id')//'';
    return _error($c,400,'Invalid request id.') unless $id=~/\A\d+\z/;
    my ($item)=_dbh()->selectrow_array('SELECT listing_id FROM '._plugin_table('borrow_requests').' WHERE id=?',undef,$id);
    return _error($c,404,'Request not found.') unless $item;
    my $key="libraryshare:listing:$item";
    my ($locked)=_dbh()->selectrow_array('SELECT GET_LOCK(?,5)',undef,$key);
    return _error($c,409,'Another lending operation is in progress. Please retry.') unless $locked;
    my $result;
    try {
        require Koha::Database;
        Koha::Database->new->schema->txn_do(sub {$result=_request_action($c)});
    } catch {
        $c->app->log->error("LibraryShare request: $_");
        $result=_error($c,500,'The lending operation failed. Please ask library staff to check its status.');
    };
    _dbh()->selectrow_array('SELECT RELEASE_LOCK(?)',undef,$key);
    return $result;
}
sub _request_action {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $id = $c->stash('request_id');
    return _error( $c, 400, 'Invalid request id.' ) unless $id && $id =~ /\A\d+\z/;
    my $action = $c->stash('request_action') // '';
    my $dbh = _dbh();
    my $req = $dbh->selectrow_hashref(
        'SELECT r.*, l.itemnumber, l.title FROM ' . _plugin_table('borrow_requests')
        . ' r JOIN ' . _plugin_table('listings') . ' l ON l.id = r.listing_id WHERE r.id = ?',
        undef, $id
    );
    return _error( $c, 404, 'Request not found.' ) unless $req;
    my $is_owner = $req->{owner_borrowernumber} == $patron->borrowernumber;
    my $is_borrower = $req->{borrower_borrowernumber} == $patron->borrowernumber;
    return _error( $c, 403, 'You are not a participant in this request.' ) unless $is_owner || $is_borrower;
    my $body = _json_body($c);

    if ( $action eq 'accept' ) {
        return _error( $c, 403, 'Only the lender can accept this request.' ) unless $is_owner;
        return _error( $c, 409, 'This request is no longer pending.' ) unless $req->{status} eq 'pending';
        $dbh->do(
            'UPDATE ' . _plugin_table('borrow_requests') . ' SET status = ?, lender_message = ? WHERE id = ? AND status = ?',
            undef, 'accepted', substr( $body->{message} // '', 0, 1000 ), $id, 'pending'
        );
        _notify(
            $dbh, $req->{borrower_borrowernumber}, 'request_accepted',
            'Your borrow request was accepted', $req->{title}, '/cgi-bin/koha/opac-main.pl',
            'request_accepted:' . $id
        );
        return $c->render( status => 200, json => { id => 0 + $id, status => 'accepted' } );
    }
    if ( $action eq 'decline' || $action eq 'cancel' ) {
        return _error($c,403,'Only the lender can decline.') if $action eq 'decline' && !$is_owner;
        return _error($c,403,'Only the lender can cancel an active checkout.') if $req->{status} eq 'approved' && !$is_owner;
        return _error( $c, 409, 'This request can no longer be changed.' )
            unless $req->{status} =~ /\A(?:pending|accepted|approved)\z/;
        if ( $req->{status} eq 'approved' ) {
            my $result = _checkin($req->{itemnumber},$req);
            return _error( $c, 502, 'Koha could not check the item in; the request was not closed.' ) unless $result;
        }
        $dbh->do(
            'UPDATE ' . _plugin_table('borrow_requests') . ' SET status = ? WHERE id = ?',
            undef, ($action eq 'decline' ? 'declined' : 'cancelled'), $id
        );
        $dbh->do('UPDATE '._plugin_table('pickup_slots').' SET status="cancelled" WHERE request_id=?',undef,$id);
        $dbh->do('INSERT INTO '._plugin_table('handoff_events').' (request_id,actor_borrowernumber,event_kind,note) VALUES (?,?,?,?)',undef,$id,$patron->borrowernumber,$action,substr($body->{notes}//'',0,1000));
        return $c->render( status => 200, json => { id => 0 + $id, status => ($action eq 'decline' ? 'declined' : 'cancelled') } );
    }
    if ($action eq 'reschedule') {
        return _error($c,403,'Only the lender can reschedule.') unless $is_owner;
        return _error($c,409,'Only booked pickups can be rescheduled.') unless $req->{status} eq 'approved';
        my $sid=$body->{slot_id}//'';
        return _error($c,400,'Choose a pickup slot.') unless $sid=~/\A\d+\z/;
        my $slot=$dbh->selectrow_hashref('SELECT * FROM '._plugin_table('pickup_slots').' WHERE id=? AND listing_id=? AND status="open" AND starts_at>NOW()',undef,$sid,$req->{listing_id});
        return _error($c,409,'Pickup slot is unavailable.') unless $slot;
        return unless _pickup_slot_open($c,$slot);
        my $updated=$dbh->do('UPDATE '._plugin_table('pickup_slots').' SET status="booked",request_id=? WHERE id=? AND status="open"',undef,$id,$sid);
        unless ($updated && $updated ne '0E0') {return _error($c,409,'Pickup slot was taken.')}
        $dbh->do('UPDATE '._plugin_table('pickup_slots').' SET status="cancelled" WHERE id=?',undef,$req->{pickup_slot_id});
        $dbh->do('UPDATE '._plugin_table('borrow_requests').' SET pickup_slot_id=? WHERE id=?',undef,$sid,$id);
        $dbh->do('INSERT INTO '._plugin_table('handoff_events').' (request_id,actor_borrowernumber,event_kind,to_location,to_starts_at,to_due_date,note) VALUES (?,?,"rescheduled",?,?,?,?)',undef,$id,$patron->borrowernumber,$slot->{location},$slot->{starts_at},$req->{due_date},substr($body->{notes}//'',0,1000));
        return $c->render(json=>{saved=>1});
    }
    if ( $action eq 'schedule' ) {
        return unless _agreements_ok($c,$patron);
        my ($active)=$dbh->selectrow_array('SELECT id FROM '._plugin_table('listings').' WHERE id=? AND status="active"',undef,$req->{listing_id});
        return _error($c,409,'This listing is no longer active.') unless $active;
        require Koha::Plugin::Com::LibraryShare::Controller::Extended;
        return _error($c,403,'The borrower must accept the current agreements before checkout.')
          if @{Koha::Plugin::Com::LibraryShare::Controller::Extended::pending($req->{borrower_borrowernumber})};
        return _error( $c, 403, 'Only the lender can schedule the pickup.' ) unless $is_owner;
        return _error( $c, 409, 'Accept the request before scheduling pickup.' ) unless $req->{status} eq 'accepted';
        my $slot_id = $body->{slot_id} // '';
        return _error( $c, 400, 'Choose an available pickup time.' ) unless $slot_id =~ /\A\d+\z/;
        my $days = $body->{loan_days} // 14;
        my $standing=Koha::Plugin::Com::LibraryShare::Stats::recompute($req->{borrower_borrowernumber});
        my ($base_days)=$dbh->selectrow_array('SELECT default_loan_days FROM '._plugin_table('listings').' WHERE id=?',undef,$req->{listing_id});
        my $max_days=$base_days;
        $max_days+=_setting($dbh,'longer_loan_bonus_days',7) if _setting($dbh,'gamification_enabled',1) && $standing->{share_credits}>=_setting($dbh,'longer_loan_threshold',50);
        return _error($c,400,"This member can borrow this item for up to $max_days days.") if $days=~/\A\d+\z/ && $days>$max_days;
        return _error( $c, 400, 'Loan length must be between 1 and 90 days.' )
            unless $days =~ /\A\d+\z/ && $days >= 1 && $days <= 90;
        my $slot = $dbh->selectrow_hashref(
            'SELECT * FROM ' . _plugin_table('pickup_slots')
            . ' WHERE id = ? AND listing_id = ? AND status = ? AND starts_at > NOW() FOR UPDATE',
            undef, $slot_id, $req->{listing_id}, 'open'
        );
        unless ($slot) {
            return _error( $c, 409, 'That pickup time was just taken. Choose another slot.' );
        }
        return unless _pickup_slot_open($c,$slot);
        my $reserved = $dbh->do(
            'UPDATE ' . _plugin_table('pickup_slots') . ' SET status = ?, request_id = ? WHERE id = ? AND status = ?',
            undef, 'booked', $id, $slot_id, 'open'
        );
        unless ($reserved && $reserved ne '0E0') {
            return _error( $c, 409, 'That pickup time was just taken. Choose another slot.' );
        }
        my ($due)=$dbh->selectrow_array('SELECT DATE_ADD(?,INTERVAL ? DAY)',undef,$slot->{starts_at},$days);
        my $checkout = _checkout( $req->{itemnumber}, $req->{borrower_borrowernumber}, $due );
        unless ($checkout) {
            $dbh->do(
                'UPDATE ' . _plugin_table('pickup_slots') . ' SET status = ?, request_id = NULL WHERE id = ? AND request_id = ?',
                undef, 'open', $slot_id, $id
            );
            return _error( $c, 502, 'Koha rejected the checkout. Check the patron and item circulation rules.' );
        }
        $dbh->do(
            'UPDATE ' . _plugin_table('borrow_requests')
            . ' SET status = ?, pickup_slot_id = ?, checkout_id = ?, due_date = ? WHERE id = ? AND status = ?',
            undef, 'approved', $slot_id, $checkout->{issue_id}, $due, $id, 'accepted'
        );
        $dbh->do(
            'INSERT INTO ' . _plugin_table('handoff_events')
            . ' (request_id, actor_borrowernumber, event_kind, to_location, to_starts_at, to_due_date, note) VALUES (?, ?, ?, ?, ?, ?, ?)',
            undef, $id, $patron->borrowernumber, 'scheduled', $slot->{location}, $slot->{starts_at}, $due, substr( $body->{notes} // '', 0, 1000 )
        );
        return $c->render( status => 200, json => { id => 0 + $id, status => 'approved', due_date => $due } );
    }
    if ( $action eq 'return' ) {
        return _error( $c, 403, 'Only the lender can mark this item returned.' ) unless $is_owner;
        return _error( $c, 409, 'This item is not currently checked out through LibraryShare.' ) unless $req->{status} eq 'approved';
        my $result = _checkin($req->{itemnumber},$req);
        return _error( $c, 502, 'Koha could not check the item in.' ) unless $result;
        $dbh->do( 'UPDATE ' . _plugin_table('borrow_requests') . ' SET status = ?, returned_at = NOW() WHERE id = ?', undef, 'returned', $id );
        $dbh->do(
            'INSERT INTO ' . _plugin_table('handoff_events')
            . ' (request_id, actor_borrowernumber, event_kind, note) VALUES (?, ?, ?, ?)',
            undef, $id, $patron->borrowernumber, 'returned', ''
        );
        _record_completed_loan($dbh, $req);
        _notify(
            $dbh, $req->{borrower_borrowernumber}, 'loan_returned',
            'Your loan was marked returned', $req->{title}, '/cgi-bin/koha/opac-main.pl',
            'loan_returned:' . $id
        );
        return $c->render( status => 200, json => { id => 0 + $id, status => 'returned' } );
    }
    return _error( $c, 404, 'Unknown request action.' );
}

sub _pickup_slot_open {
    my ($c,$slot)=@_;
    require Koha::Plugin::Com::LibraryShare::PickupAvailability;
    my $open=eval {Koha::Plugin::Com::LibraryShare::PickupAvailability::filter_open(_dbh(),[$slot])};
    unless ($open && @$open) {
        _error($c,409,'The branch is no longer available at that time. Refresh pickup availability or ask staff to check branch hours and closures.');
        return;
    }
    return 1;
}

sub slots {
    my ($c) = @_;
    my $listing_id = $c->param('listing_id') // '';
    return _error( $c, 400, 'Choose a listing.' ) unless $listing_id =~ /\A\d+\z/;
    my $rows = _dbh()->selectall_arrayref(
        'SELECT id, starts_at, ends_at, branchcode, location FROM ' . _plugin_table('pickup_slots')
        . ' WHERE listing_id = ? AND status = ? AND starts_at > NOW() ORDER BY starts_at',
        { Slice => {} }, $listing_id, 'open'
    );
    require Koha::Plugin::Com::LibraryShare::PickupAvailability;
    my $open=eval {Koha::Plugin::Com::LibraryShare::PickupAvailability::filter_open(_dbh(),$rows)};
    return _error($c,400,Koha::Plugin::Com::LibraryShare::PickupAvailability::public_error($@)) unless $open;
    return $c->render( status => 200, json => { slots => $open } );
}

sub create_slot {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $listing_id = $c->stash('listing_id');
    my $body = _json_body($c);
    return _error( $c, 400, 'Invalid listing id.' ) unless $listing_id =~ /\A\d+\z/;
    return _error( $c, 400, 'Choose a date range and a pickup location.' )
        unless $body->{date_from} && $body->{date_to} && ($body->{location}//'') =~ /\S/;
    my $dbh = _dbh();
    my $listing = $dbh->selectrow_hashref(
        'SELECT owner_borrowernumber, pickup_branch FROM ' . _plugin_table('listings') . ' WHERE id = ?',
        undef, $listing_id
    );
    return _error( $c, 404, 'Listing not found.' ) unless $listing;
    return _error( $c, 403, 'Only the lender can offer pickup times.' )
        unless $listing->{owner_borrowernumber} == $patron->borrowernumber;
    require Koha::Plugin::Com::LibraryShare::PickupAvailability;
    my $slots;
    my $ok = eval {
        $dbh->begin_work;
        # Serialize concurrent generators for this listing before checking overlaps.
        $listing = $dbh->selectrow_hashref(
            'SELECT owner_borrowernumber,pickup_branch FROM '._plugin_table('listings').' WHERE id=? FOR UPDATE',
            undef,$listing_id);
        die "Listing is no longer available.\n" unless $listing && $listing->{owner_borrowernumber} == $patron->borrowernumber;
        my $existing=$dbh->selectall_arrayref(
            'SELECT starts_at,ends_at FROM '._plugin_table('pickup_slots').' WHERE listing_id=? AND status<>"cancelled"',
            {Slice=>{}},$listing_id);
        $slots=Koha::Plugin::Com::LibraryShare::PickupAvailability::for_branch($dbh,$listing->{pickup_branch},$body,$existing);
        for my $slot (@$slots) {
            $dbh->do('INSERT INTO '._plugin_table('pickup_slots')
                .' (listing_id,owner_borrowernumber,starts_at,ends_at,branchcode,location,status) VALUES (?,?,?,?,?,?,"open")',
                undef,$listing_id,$patron->borrowernumber,$slot->{starts_at},$slot->{ends_at},
                $listing->{pickup_branch},substr($body->{location},0,200));
            ($slot->{id})=$dbh->selectrow_array('SELECT LAST_INSERT_ID()');
        }
        $dbh->commit;
        1;
    };
    unless ($ok) {
        my $error=$@;
        $c->app->log->error("LibraryShare pickup generation: $error");
        eval {$dbh->rollback unless $dbh->{AutoCommit}};
        # Only expose intentional validation messages, not database internals.
        return _error($c,400,$error =~ /\A(?:Enter |End date |Choose |Daily |Staff must |Listing is )/ ? $error : 'Could not generate pickup times. Ask staff to check branch hours and the Koha calendar.');
    }
    return $c->render(status=>201,json=>{created=>scalar(@$slots),slots=>$slots,
        message=>@$slots ? 'Pickup availability added.' : 'No new one-hour slots fit this range. Dates may be closed, past, already offered, or shorter than one hour.'});
}

sub wanted {
    my ($c) = @_;
    my $dbh = _dbh();
    my $patron = _patron($c);
    my $viewer = $patron ? $patron->borrowernumber : 0;
    my $status=$c->param('status')//'open';
    return _error($c,400,'Invalid wanted status.') unless $status=~/\A(?:open|closed|fulfilled)\z/;
    my $rows = $dbh->selectall_arrayref(
        'SELECT w.id, w.title, w.category, w.description, w.status, w.created_at, b.firstname, b.surname,'
        . ' (SELECT COUNT(*) FROM ' . _plugin_table('wanted_interests') . ' wi WHERE wi.wanted_id = w.id) AS interest_count,'
        . ' (w.patron_borrowernumber = ?) AS is_mine,'
        . ' EXISTS(SELECT 1 FROM ' . _plugin_table('wanted_interests') . ' mine WHERE mine.wanted_id = w.id AND mine.patron_borrowernumber = ?) AS my_interest FROM '
        . _plugin_table('wanted_items') . ' w LEFT JOIN borrowers b ON b.borrowernumber = w.patron_borrowernumber WHERE w.status = ? ORDER BY w.created_at DESC LIMIT 100',
        { Slice => {} }, $viewer, $viewer, $status
    );
    return $c->render( status => 200, json => { wanted => $rows } );
}

sub create_wanted {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $body = _json_body($c);
    return _error( $c, 400, 'A wanted item title is required.' ) unless $body->{title} && $body->{title} =~ /\S/;
    my $dbh = _dbh();
    $dbh->do(
        'INSERT INTO ' . _plugin_table('wanted_items') . ' (patron_borrowernumber, title, category, description, status) VALUES (?, ?, ?, ?, ?)',
        undef, $patron->borrowernumber, substr( $body->{title}, 0, 200 ), substr( $body->{category} // '', 0, 80 ), substr( $body->{description} // '', 0, 1000 ), 'open'
    );
    my ($id) = $dbh->selectrow_array('SELECT LAST_INSERT_ID()');
    return $c->render( status => 201, json => { id => 0 + $id, status => 'open' } );
}

sub wanted_interest {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $id = $c->stash('wanted_id') // '';
    return _error( $c, 400, 'Invalid wanted item id.' ) unless $id =~ /\A\d+\z/;
    my $body = _json_body($c);
    my $dbh = _dbh();
    my $wanted = $dbh->selectrow_hashref(
        'SELECT patron_borrowernumber, status FROM ' . _plugin_table('wanted_items') . ' WHERE id = ?',
        undef, $id
    );
    return _error( $c, 404, 'Wanted item not found.' ) unless $wanted && $wanted->{status} eq 'open';
    return _error( $c, 400, 'You cannot express interest in your own request.' )
        if $wanted->{patron_borrowernumber} == $patron->borrowernumber;
    if ( $body->{interested} ) {
        $dbh->do(
            'INSERT IGNORE INTO ' . _plugin_table('wanted_interests') . ' (wanted_id, patron_borrowernumber) VALUES (?, ?)',
            undef, $id, $patron->borrowernumber
        );
    } else {
        $dbh->do(
            'DELETE FROM ' . _plugin_table('wanted_interests') . ' WHERE wanted_id = ? AND patron_borrowernumber = ?',
            undef, $id, $patron->borrowernumber
        );
    }
    return $c->render( status => 200, json => { interested => $body->{interested} ? 1 : 0 } );
}

sub fulfil_wanted {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $id = $c->stash('wanted_id') // '';
    return _error( $c, 400, 'Invalid wanted item id.' ) unless $id =~ /\A\d+\z/;
    my $dbh = _dbh();
    my $wanted = $dbh->selectrow_hashref(
        'SELECT * FROM ' . _plugin_table('wanted_items') . ' WHERE id = ? AND status = ?',
        undef, $id, 'open'
    );
    return _error( $c, 404, 'Open wanted item not found.' ) unless $wanted;
    return _error( $c, 403, 'Only the person who posted this can mark it fulfilled.' )
        unless $wanted->{patron_borrowernumber} == $patron->borrowernumber;
    $dbh->do(
        'UPDATE ' . _plugin_table('wanted_items') . ' SET status = ? WHERE id = ? AND status = ?',
        undef, 'fulfilled', $id, 'open'
    );
    return $c->render( status => 200, json => { id => 0 + $id, status => 'fulfilled' } );
}

sub review {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $body = _json_body($c);
    return _error( $c, 400, 'A completed request and a 1–5 star rating are required.' )
        unless $body->{request_id} && $body->{rating} && $body->{rating} =~ /\A[1-5]\z/;
    my $dbh = _dbh();
    my $req = $dbh->selectrow_hashref(
        'SELECT * FROM ' . _plugin_table('borrow_requests') . ' WHERE id = ? AND status = ?',
        undef, $body->{request_id}, 'returned'
    );
    return _error( $c, 404, 'Only returned loans can be reviewed.' ) unless $req;
    return _error( $c, 403, 'You are not a participant in this loan.' )
        unless $req->{owner_borrowernumber} == $patron->borrowernumber || $req->{borrower_borrowernumber} == $patron->borrowernumber;
    $dbh->do(
        'INSERT INTO ' . _plugin_table('reviews') . ' (request_id, reviewer_borrowernumber, reviewee_borrowernumber, rating, body) VALUES (?, ?, ?, ?, ?)',
        undef, $req->{id}, $patron->borrowernumber,
        ($req->{owner_borrowernumber} == $patron->borrowernumber ? $req->{borrower_borrowernumber} : $req->{owner_borrowernumber}),
        $body->{rating}, substr( $body->{body} // '', 0, 1000 )
    );
    my ($review_id)=_dbh()->selectrow_array('SELECT LAST_INSERT_ID()');
    return $c->render( status => 201, json => { saved => 1, id=>0+$review_id } );
}

sub list_reviews {
    my ($c) = @_;
    my $borrowernumber = $c->param('borrowernumber') // '';
    return _error( $c, 400, 'A patron id is required.' ) unless $borrowernumber =~ /\A\d+\z/;
    my $rows = _dbh()->selectall_arrayref(
        'SELECT r.id, r.request_id, r.reviewer_borrowernumber, r.rating, r.body, r.created_at, b.firstname, b.surname FROM '
        . _plugin_table('reviews') . ' r LEFT JOIN borrowers b ON b.borrowernumber = r.reviewer_borrowernumber WHERE r.reviewee_borrowernumber = ? ORDER BY r.created_at DESC LIMIT 100',
        { Slice => {} }, $borrowernumber
    );
    my ($average) = _dbh()->selectrow_array(
        'SELECT AVG(rating) FROM ' . _plugin_table('reviews') . ' WHERE reviewee_borrowernumber = ?',
        undef, $borrowernumber
    );
    return $c->render( status => 200, json => { reviews => $rows, average_rating => 0 + ($average || 0) } );
}

sub messages {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $body = _json_body($c);
    my $request_id = $body->{request_id} || $c->param('request_id') || '';
    return _error( $c, 400, 'A request id is required.' ) unless $request_id =~ /\A\d+\z/;
    my $dbh = _dbh();
    my $request = $dbh->selectrow_hashref(
        'SELECT * FROM ' . _plugin_table('borrow_requests') . ' WHERE id = ?',
        undef, $request_id
    );
    return _error( $c, 404, 'Request not found.' ) unless $request;
    return _error( $c, 403, 'You are not a participant in this request.' )
        unless $request->{owner_borrowernumber} == $patron->borrowernumber
        || $request->{borrower_borrowernumber} == $patron->borrowernumber;
    if ( $c->req->method eq 'POST' ) {
        my $message = $body->{message} // '';
        return _error( $c, 400, 'Message text is required.' ) unless $message =~ /\S/;
        $message = substr( $message, 0, 2000 );
        $dbh->do(
            'INSERT INTO ' . _plugin_table('request_messages')
            . ' (request_id, sender_borrowernumber, message) VALUES (?, ?, ?)',
            undef, $request_id, $patron->borrowernumber, $message
        );
        my $recipient = $request->{owner_borrowernumber} == $patron->borrowernumber
            ? $request->{borrower_borrowernumber} : $request->{owner_borrowernumber};
        _notify(
            $dbh, $recipient, 'message', 'New message about a loan', substr($message, 0, 140),
            '/cgi-bin/koha/opac-main.pl', 'message:' . $request_id . ':' . time
        );
        return $c->render( status => 201, json => { sent => 1 } );
    }
    my $rows = $dbh->selectall_arrayref(
        'SELECT m.id, m.sender_borrowernumber, m.message, m.created_at, b.firstname, b.surname FROM '
        . _plugin_table('request_messages') . ' m LEFT JOIN borrowers b ON b.borrowernumber = m.sender_borrowernumber WHERE m.request_id = ? ORDER BY m.created_at',
        { Slice => {} }, $request_id
    );
    return $c->render( status => 200, json => { messages => $rows } );
}

sub notifications {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $rows = _dbh()->selectall_arrayref(
        'SELECT id, kind, title, body, link, read_at, created_at FROM '
        . _plugin_table('notifications') . ' WHERE patron_borrowernumber = ? ORDER BY created_at DESC LIMIT 100',
        { Slice => {} }, $patron->borrowernumber
    );
    return $c->render( status => 200, json => { notifications => $rows } );
}

sub notification_read {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $id = $c->stash('notification_id') // '';
    return _error( $c, 400, 'Invalid notification id.' ) unless $id =~ /\A\d+\z/;
    _dbh()->do(
        'UPDATE ' . _plugin_table('notifications') . ' SET read_at = NOW() WHERE id = ? AND patron_borrowernumber = ?',
        undef, $id, $patron->borrowernumber
    );
    return $c->render( status => 200, json => { read => 1 } );
}

sub community {
    my ($c) = @_;
    my $dbh = _dbh();
    my ($listing_count) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM ' . _plugin_table('listings') . ' l WHERE ' . _available_sql(),
        undef, 'active'
    );
    my ($loan_count) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM ' . _plugin_table('borrow_requests') . ' WHERE status IN (?, ?)',
        undef, 'approved', 'returned'
    );
    my ($lender_count) = $dbh->selectrow_array(
        'SELECT COUNT(DISTINCT owner_borrowernumber) FROM ' . _plugin_table('listings') . ' WHERE status = ?',
        undef, 'active'
    );
    my $categories = $dbh->selectall_arrayref(
        'SELECT category, COUNT(*) AS item_count FROM ' . _plugin_table('listings')
        . ' WHERE status = ? GROUP BY category ORDER BY item_count DESC LIMIT 8',
        { Slice => {} }, 'active'
    );
    my $monthly = $dbh->selectall_arrayref(
        'SELECT DATE_FORMAT(created_at, "%Y-%m") AS month, COUNT(*) AS loans FROM '
        . _plugin_table('borrow_requests') . ' WHERE status IN (?, ?) GROUP BY month ORDER BY month DESC LIMIT 12',
        { Slice => {} }, 'approved', 'returned'
    );
    return $c->render(
        status => 200,
        json => {
            totals => {
                listings => 0 + ($listing_count || 0),
                loans => 0 + ($loan_count || 0),
                active_lenders => 0 + ($lender_count || 0),
            },
            categories => $categories,
            monthly_loans => $monthly,
        }
    );
}

sub leaderboard {
    my ($c) = @_;
    my $rows = _dbh()->selectall_arrayref(
        'SELECT s.borrowernumber, b.firstname, b.surname, s.loans_as_lender, s.distinct_items_lent, s.level, s.share_credits FROM '
        . _plugin_table('patron_stats') . ' s JOIN borrowers b ON b.borrowernumber = s.borrowernumber LEFT JOIN '._plugin_table('preferences').' p ON p.borrowernumber=s.borrowernumber WHERE COALESCE(p.show_in_leaderboard,1)=1 ORDER BY s.loans_as_lender DESC, s.share_credits DESC LIMIT 50',
        { Slice => {} }
    );
    return $c->render( status => 200, json => { leaderboard => $rows } );
}

sub challenges {
    my ($c) = @_;
    my $patron = _patron($c);
    my $sql = 'SELECT c.id, c.title, c.description, c.goal, c.start_date, c.end_date, c.active, p.progress, p.completed_at FROM '
        . _plugin_table('challenges') . ' c LEFT JOIN ' . _plugin_table('challenge_progress') . ' p ON p.challenge_id = c.id';
    my @bind;
    if ($patron) {
        $sql .= ' AND p.borrowernumber = ?';
        push @bind, $patron->borrowernumber;
    } else {
        $sql .= ' AND p.borrowernumber IS NULL';
    }
    $sql .= ' WHERE c.active = 1 AND c.end_date >= CURDATE() ORDER BY c.end_date';
    my $rows = _dbh()->selectall_arrayref( $sql, { Slice => {} }, @bind );
    return $c->render( status => 200, json => { challenges => $rows } );
}

sub impact {
    my ($c) = @_;
    my $patron = _patron($c);
    my $community = _dbh()->selectrow_hashref(
        'SELECT COUNT(*) AS loans, COUNT(DISTINCT owner_borrowernumber) AS lenders FROM '
        . _plugin_table('borrow_requests') . ' WHERE status = ?',
        undef, 'returned'
    ) || {};
    my $own = $patron ? _dbh()->selectrow_hashref(
        'SELECT loans_as_lender, loans_as_borrower, distinct_items_lent, est_value_saved, level, share_credits FROM '
        . _plugin_table('patron_stats') . ' WHERE borrowernumber = ?',
        undef, $patron->borrowernumber
    ) : undef;
    return $c->render( status => 200, json => { community => $community, patron => $own || {} } );
}

sub accept_legal {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $body = _json_body($c);
    return _error( $c, 400, 'Document and version are required.' )
        unless $body->{document_key} && $body->{version};
    my ($version)=_dbh()->selectrow_array('SELECT version FROM '._plugin_table('documents').' WHERE document_key=?',undef,$body->{document_key});
    return _error($c,409,'Read and accept the current agreement version.') unless defined($version) && $version eq $body->{version};
    _dbh()->do(
        'INSERT IGNORE INTO ' . _plugin_table('legal_acceptances')
        . ' (borrowernumber, document_key, document_version) VALUES (?, ?, ?)',
        undef, $patron->borrowernumber, substr( $body->{document_key}, 0, 80 ), substr( $body->{version}, 0, 40 )
    );
    return $c->render( status => 201, json => { accepted => 1 } );
}

sub kudos {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    my $body = _json_body($c);
    return _error( $c, 400, 'A returned request and a thank-you note are required.' )
        unless $body->{request_id} && $body->{message} && $body->{message} =~ /\S/;
    my $dbh = _dbh();
    my $req = $dbh->selectrow_hashref(
        'SELECT * FROM ' . _plugin_table('borrow_requests') . ' WHERE id = ? AND status = ?',
        undef, $body->{request_id}, 'returned'
    );
    return _error( $c, 404, 'Only returned loans can receive a thank-you note.' ) unless $req;
    return _error( $c, 403, 'Only the borrower can thank the lender.' )
        unless $req->{borrower_borrowernumber} == $patron->borrowernumber;
    $dbh->do(
        'INSERT INTO ' . _plugin_table('kudos') . ' (request_id, sender_borrowernumber, recipient_borrowernumber, message) VALUES (?, ?, ?, ?)',
        undef, $req->{id}, $patron->borrowernumber, $req->{owner_borrowernumber}, substr( $body->{message}, 0, 500 )
    );
    _notify(
        $dbh, $req->{owner_borrowernumber}, 'kudos', 'You received a thank-you note',
        substr( $body->{message}, 0, 200 ), '/cgi-bin/koha/opac-main.pl', 'kudos:' . $req->{id}
    );
    return $c->render( status => 201, json => { saved => 1 } );
}

sub admin_settings {
    my ($c) = @_;
    my $patron = _need_patron($c) or return;
    return _error( $c, 403, 'Koha plugin administration permission is required.' ) unless _is_admin($patron);
    my $dbh = _dbh();
    if ( $c->req->method eq 'POST' ) {
        my $body = _json_body($c);
        my $item_type = $body->{item_type_code} // '';
        return _error( $c, 400, 'Enter a Koha item type code.' ) unless $item_type =~ /\A[A-Za-z0-9_-]{1,10}\z/;
        my $exists = $dbh->selectrow_array(
            'SELECT itemtype FROM itemtypes WHERE itemtype = ?',
            undef, $item_type
        );
        return _error( $c, 400, 'That Koha item type does not exist. Create it in Koha first.' ) unless $exists;
        my $credits = $body->{credits_per_completed_loan} // 1;
        my $default_days = $body->{default_loan_days} // 14;
        return _error( $c, 400, 'Credits must be between 0 and 100.' )
            unless $credits =~ /\A\d+\z/ && $credits <= 100;
        return _error( $c, 400, 'Default loan days must be between 1 and 90.' )
            unless $default_days =~ /\A\d+\z/ && $default_days >= 1 && $default_days <= 90;
        for my $setting (
            [ item_type_code => $item_type ],
            [ credits_per_completed_loan => $credits ],
            [ default_loan_days => $default_days ],
        ) {
            $dbh->do(
                'INSERT INTO ' . _plugin_table('settings') . ' (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)',
                undef, $setting->[0], $setting->[1]
            );
        }
        return $c->render( status => 200, json => { saved => 1 } );
    }
    my $rows = $dbh->selectall_arrayref(
        'SELECT setting_key, setting_value FROM ' . _plugin_table('settings'),
        { Slice => {} }
    );
    my %settings = map { $_->{setting_key} => $_->{setting_value} } @$rows;
    $settings{item_type_code} //= C4::Context->preference('LibraryShareItemType') || 'PEERLEND';
    $settings{credits_per_completed_loan} //= 1;
    $settings{default_loan_days} //= 14;
    return $c->render( status => 200, json => { settings => \%settings } );
}

sub _is_admin {
    my ($patron) = @_;
    return unless $patron && $patron->can('userid') && $patron->userid;
    my $staff=eval {
        require C4::Auth;
        C4::Auth::haspermission( $patron->userid, { plugins => 'manage' } ) ? 1 : 0;
    } || 0;
    return 1 if $staff;
    return eval {_dbh()->selectrow_array('SELECT 1 FROM '._plugin_table('roles').' WHERE borrowernumber=?',undef,$patron->borrowernumber)} || 0;
}

sub _record_completed_loan {
    my ( $dbh, $request ) = @_;
    require Koha::Plugin::Com::LibraryShare::Stats;
    Koha::Plugin::Com::LibraryShare::Stats::recompute($_) for ($request->{owner_borrowernumber},$request->{borrower_borrowernumber});
}

sub _notify {
    my ( $dbh, $recipient, $kind, $title, $body, $link, $dedupe ) = @_;
    return unless $recipient;
    $dbh->do(
        'INSERT IGNORE INTO ' . _plugin_table('notifications')
        . ' (patron_borrowernumber, kind, title, body, link, dedupe_key) VALUES (?, ?, ?, ?, ?, ?)',
        undef, $recipient, $kind, $title, substr( $body // '', 0, 1000 ), $link // '', $dedupe
    );
}

sub _setting {
    my ( $dbh, $key, $default ) = @_;
    my $value = $dbh->selectrow_array(
        'SELECT setting_value FROM ' . _plugin_table('settings') . ' WHERE setting_key = ?',
        undef, $key
    );
    return defined $value ? $value : $default;
}

sub _has_overdues {
    my ($borrowernumber) = @_;
    my $count = _dbh()->selectrow_array(
        'SELECT COUNT(*) FROM issues WHERE borrowernumber = ? AND date_due < NOW()',
        undef, $borrowernumber
    ) || 0;
    my $restricted = _dbh()->selectrow_array(
        'SELECT COUNT(*) FROM borrowers WHERE borrowernumber = ? AND (gonenoaddress = 1 OR lost = 1 OR dateexpiry < CURDATE() OR (debarred IS NOT NULL AND debarred >= CURDATE()))',
        undef, $borrowernumber
    ) || 0;
    return $count || $restricted;
}

sub _checkout {
    my ( $itemnumber, $borrowernumber, $due ) = @_;
    return unless $itemnumber && $borrowernumber;
    return try {
        require C4::Circulation;
        require Koha::Patrons;
        require Koha::Items;
        my $patron = Koha::Patrons->find($borrowernumber) or die 'Borrower not found';
        my $item = Koha::Items->find($itemnumber) or die 'Item not found';
        return if $item->checkout || _has_overdues($borrowernumber);
        require Koha::DateUtils;
        my $date=Koha::DateUtils::dt_from_string($due,'iso');
        my ($impossible,$confirm)=C4::Circulation::CanBookBeIssued($patron,$item->barcode,$date,0,0,{});
        return if keys %{$impossible//{}} || keys %{$confirm//{}};
        my $issue = C4::Circulation::AddIssue( $patron, $item->barcode, $date, undef, undef, undef, {} );
        return unless $issue;
        return { issue_id => $issue->issue_id };
    }
    catch { die $_; };
}

sub _checkin {
    my ($itemnumber,$request) = @_;
    return unless $itemnumber;
    return try {
        require C4::Circulation;
        require Koha::Items;
        my $item = Koha::Items->find($itemnumber) or die 'Item not found';
        my $issue=$item->checkout or return;
        return unless $request && $issue->issue_id==$request->{checkout_id} && $issue->borrowernumber==$request->{borrower_borrowernumber};
        my ( $success, $messages, $issues ) = C4::Circulation::AddReturn( $item->barcode, $item->homebranch );
        return $success ? 1 : undef;
    }
    catch { die $_; };
}

sub _mysql_datetime {
    my ($epoch) = @_;
    return POSIX::strftime( '%Y-%m-%d %H:%M:%S', localtime($epoch) );
}

sub _agreements_ok {
    my ($c,$patron)=@_;
    require Koha::Plugin::Com::LibraryShare::Controller::Extended;
    if (@{Koha::Plugin::Com::LibraryShare::Controller::Extended::pending($patron->borrowernumber)}) {
        _error($c,403,'Read and accept the current agreements before lending or borrowing.');return;
    }
    return 1;
}

sub _iso_to_mysql {
    my ($value) = @_;
    return unless defined $value;
    $value =~ s/T/ /;
    $value =~ s/Z$//;
    $value =~ s/[+-]\d\d:\d\d$//;
    $value .= ':00' if $value =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d\z/;
    return $value;
}

1;
