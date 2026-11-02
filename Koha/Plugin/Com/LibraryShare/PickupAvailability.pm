package Koha::Plugin::Com::LibraryShare::PickupAvailability;
use strict;
use warnings;
use Time::Piece ();
use Time::Seconds qw(ONE_DAY);

# Work in local wall-clock strings, never in the browser's timezone.
sub date {
    my ($value) = @_;
    die "Enter valid dates (YYYY-MM-DD).\n" unless defined($value) && $value =~ /^\d{4}-\d\d-\d\d$/;
    my $d = eval { Time::Piece->strptime($value, '%Y-%m-%d') };
    die "Enter valid calendar dates.\n" unless $d && $d->ymd eq $value;
    return $d;
}
sub minutes {
    my ($v) = @_;
    die "Enter valid hours and minutes.\n" unless defined($v) && $v =~ /^([01]\d|2[0-3]):([0-5]\d)(?::00)?$/;
    return $1 * 60 + $2;
}
sub generate {
    my (%a) = @_;
    my $first = date($a{date_from});
    my $last = date($a{date_to});
    die "End date must be on or after start date.\n" if $last < $first;
    die "Choose a range of at most 93 days.\n" if ($last-$first)/ONE_DAY > 92;
    my $from = minutes($a{daily_start} || '00:00');
    my $to = minutes($a{daily_end} || '23:59');
    die "Daily end time must follow start time.\n" if $to <= $from;
    my @slots;
    for (my $d=$first; $d <= $last; $d += ONE_DAY) {
        next if $a{closed}->($d);
        my $h = $a{hours}{$d->wday - 1};
        next unless $h && defined($h->{open_time}) && defined($h->{close_time});
        my $open = minutes($h->{open_time});
        my $close = minutes($h->{close_time});
        my $start = $open > $from ? $open : $from;
        my $end = $close < $to ? $close : $to;
        for (my $m=$start; $m+60 <= $end; $m+=60) {
            my $s = $d->ymd . sprintf(' %02d:%02d:00',int($m/60),$m%60);
            my $e = $d->ymd . sprintf(' %02d:%02d:00',int(($m+60)/60),($m+60)%60);
            next if $s le $a{now};
            next if grep { $_->{starts_at} lt $e && $_->{ends_at} gt $s } @{$a{existing} || []};
            push @slots, {starts_at=>$s,ends_at=>$e};
        }
    }
    return \@slots;
}

sub branch_context {
    my ($dbh,$branch) = @_;
    my $rows = eval {
        require Koha::Libraries;
        my $library=Koha::Libraries->find($branch);
        die "Unknown pickup branch\n" unless $library;
        my @hours=$library->library_hours->as_list;
        [map {{day=>$_->day,open_time=>$_->open_time,close_time=>$_->close_time}} @hours];
    };
    unless ($rows) {
        warn "LibraryShare opening-hours lookup failed: $@";
        die "Staff must check the Koha opening-hours service and server log; branch hours could not be read.\n";
    }
    die "Staff must configure opening hours for this pickup branch in Koha Administration > Libraries.\n"
        unless @$rows;
    # Existing all-null rows mean closed, not an infrastructure failure.
    my $class;
    if (eval { require Koha::Library::Calendar; 1 }) {
        $class='Koha::Library::Calendar';
    } else {
        die $@ unless $@ =~ /Can't locate Koha\/Library\/Calendar\.pm/;
        require Koha::Calendar;
        $class='Koha::Calendar';
    }
    require DateTime;
    my $calendar = eval {$class->new(branchcode=>$branch)};
    unless ($calendar) {
        warn "LibraryShare closure calendar failed: $@";
        die "Staff must check the Koha closure calendar and server log; pickup times cannot be verified.\n";
    }
    my ($now) = $dbh->selectrow_array('SELECT NOW()');
    return {
        hours=>{map {$_->{day}=>$_} @$rows}, now=>$now,
        closed=>sub {
            my ($d)=@_;
            return $calendar->is_holiday(DateTime->new(
                year=>$d->year,month=>$d->mon,day=>$d->mday,time_zone=>'floating'));
        }
    };
}
sub public_error {
    my ($error)=@_;
    warn "LibraryShare pickup availability: $error";
    return $error if !ref($error) && $error =~ /\AStaff must /;
    return 'Pickup times could not be verified. Ask staff to check the opening-hours service and closure calendar; no unverified times are offered.';
}
sub for_branch {
    my ($dbh,$branch,$body,$existing) = @_;
    return generate(%$body,%{branch_context($dbh,$branch)},existing=>$existing);
}
sub filter_open {
    my ($dbh,$slots) = @_;
    my (%contexts,@open);
    for my $s (@$slots) {
        next unless substr($s->{starts_at},0,10) eq substr($s->{ends_at},0,10);
        next unless minutes(substr($s->{ends_at},11,5))-minutes(substr($s->{starts_at},11,5)) == 60;
        my $context=$contexts{$s->{branchcode}} ||= branch_context($dbh,$s->{branchcode});
        my $matches=generate(%$context,
            date_from=>substr($s->{starts_at},0,10),date_to=>substr($s->{ends_at},0,10),
            daily_start=>substr($s->{starts_at},11,5),daily_end=>substr($s->{ends_at},11,5));
        push @open,$s if grep {$_->{starts_at} eq $s->{starts_at} && $_->{ends_at} eq $s->{ends_at}} @$matches;
    }
    return \@open;
}
1;
