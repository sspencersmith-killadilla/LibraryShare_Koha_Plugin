package Koha::Plugin::Com::LibraryShare::Value;
use strict;
use warnings;

sub validate {
    my ($value)=@_;
    die "Enter an estimated item value from 0 to 99,999,999.99 with at most two decimal places.\n"
        unless defined($value) && !ref($value) && "$value" =~ /\A(0|[1-9]\d{0,7})(?:\.(\d{1,2}))?\z/;
    my ($whole,$fraction)=($1,$2//'');
    return $whole.'.'.substr($fraction.'00',0,2);
}

sub half {
    my ($value)=@_;
    return undef unless defined $value;
    my ($whole,$fraction)=split /\./,validate($value);
    my $cents=int(($whole*100+$fraction+1)/2);
    return sprintf('%d.%02d',int($cents/100),$cents%100);
}

# Refresh just savings, without awarding badges/credits or altering circulation.
sub refresh {
    my ($dbh,$owner)=@_;
    $dbh->do('UPDATE koha_plugin_com_libraryshare_patron_stats s SET est_value_saved='
        .'(SELECT COALESCE(SUM(ROUND(l.estimated_value/2,2)),0) FROM koha_plugin_com_libraryshare_borrow_requests r '
        .'JOIN koha_plugin_com_libraryshare_listings l ON l.id=r.listing_id '
        .'WHERE r.owner_borrowernumber=s.borrowernumber AND r.status="returned")'
        .(defined($owner)?' WHERE s.borrowernumber=?':''),undef,
        (defined($owner)?($owner):()));
}

sub migrate {
    my ($dbh)=@_;
    my ($exists)=$dbh->selectrow_array(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
        undef,'koha_plugin_com_libraryshare_listings','estimated_value');
    $dbh->do('ALTER TABLE koha_plugin_com_libraryshare_listings ADD COLUMN estimated_value DECIMAL(10,2) NULL DEFAULT NULL')
        unless $exists;
    my ($precision)=$dbh->selectrow_array(
        'SELECT NUMERIC_PRECISION FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
        undef,'koha_plugin_com_libraryshare_patron_stats','est_value_saved');
    $dbh->do('ALTER TABLE koha_plugin_com_libraryshare_patron_stats MODIFY COLUMN est_value_saved DECIMAL(18,2) NOT NULL DEFAULT 0')
        if $precision && $precision < 18;
    refresh($dbh);
}
1;
