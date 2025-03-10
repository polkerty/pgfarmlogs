#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(:config no_ignore_case);
use DBI;
use JSON::PP;

# Magic delimiter
my $MAGIC = "==~_~===-=-===~_~==";

sub chunk_log {
    my ($log_text, $magic) = @_;
    my @chunks;
    my $current_filename = "head";
    my $pos = 0;

    while (1) {
        my $next_magic = index($log_text, $magic, $pos);
        if ($next_magic == -1) {
            push @chunks, [$current_filename, substr($log_text, $pos)];
            last;
        }
        push @chunks, [$current_filename, substr($log_text, $pos, $next_magic - $pos)];
        $pos = $next_magic + length($magic);

        my $next_magic2 = index($log_text, $magic, $pos);
        if ($next_magic2 == -1) {
            $current_filename = substr($log_text, $pos);
            last;
        }
        $current_filename = substr($log_text, $pos, $next_magic2 - $pos);
        $pos = $next_magic2 + length($magic);
    }

    return @chunks;
}

sub fetch_and_chunk_logs {
    my ($conninfo_or_params, $lookback, $max_chars) = @_;

    # Connect with AutoCommit => 0, so we can DECLARE a cursor in a transaction
    my $dbh;
    if (ref($conninfo_or_params) eq 'HASH') {
        $dbh = DBI->connect(
            "dbi:Pg:dbname=$conninfo_or_params->{dbname};host=$conninfo_or_params->{host};port=$conninfo_or_params->{port}",
            $conninfo_or_params->{user},
            $conninfo_or_params->{password},
            {
                AutoCommit => 0,
                RaiseError => 1,
                PrintError => 0,
            }
        );
    } else {
        my $conn_str = "dbi:Pg:$conninfo_or_params";
        $dbh = DBI->connect(
            $conn_str,
            undef,
            undef,
            {
                AutoCommit => 0,
                RaiseError => 1,
                PrintError => 0,
            }
        );
    }

    # Prepare a DECLARE CURSOR statement
    my $cursor_name = 'log_stream_cursor';
    my $quoted_lookback = $dbh->quote($lookback);  # e.g. '6 months'
    # We'll produce something like:   snapshot > current_date - '6 months'::interval
    my $interval_expr = $quoted_lookback . '::interval';

    my $declare_sql = <<"SQL";
DECLARE $cursor_name NO SCROLL CURSOR FOR
    SELECT
        sysname,
        snapshot,
        status,
        stage,
        log,
        branch,
        git_head_ref AS commit
    FROM build_status
    WHERE stage != 'OK'
      AND build_status.report_time IS NOT NULL
      AND snapshot > current_date - $interval_expr
    ORDER BY snapshot ASC
SQL

    # Declare the cursor
    $dbh->do($declare_sql);

    my @results;
    my $batch_size = 100;

    while (1) {
        # FETCH <batch_size> rows from the cursor
        my $fetch_sql = "FETCH $batch_size FROM $cursor_name";
        my $fetch_sth = $dbh->prepare($fetch_sql);
        $fetch_sth->execute();

        my $row_count = 0;
        while (my $row = $fetch_sth->fetchrow_hashref) {
            $row_count++;
            my $log_text = defined $row->{log} ? $row->{log} : "";

            my @pieces = chunk_log($log_text, $MAGIC);
            foreach my $piece (@pieces) {
                my ($filename, $text_section) = @$piece;
                if (length($text_section) > $max_chars) {
                    $text_section = substr($text_section, -$max_chars);
                }
                push @results, {
                    sysname  => $row->{sysname},
                    snapshot => "$row->{snapshot}", # stringified
                    status   => $row->{status},
                    stage    => $row->{stage},
                    filename => $filename =~ s/^\s+|\s+$//gr,
                    commit   => $row->{commit},
                    branch   => $row->{branch},
                    text     => $text_section,
                };
            }
        }

        $fetch_sth->finish();
        last if $row_count == 0;
    }

    # Close cursor and commit
    $dbh->do("CLOSE $cursor_name");
    $dbh->do("COMMIT");
    $dbh->disconnect;

    return \@results;
}

sub prompt_for_password {
    print "Password: ";
    my $pw = <STDIN>;
    chomp($pw);
    return $pw;
}

sub main {
    my %args;
    GetOptions(
        "h|host=s"       => \$args{host},
        "p|port=i"       => \$args{port},
        "d|dbname=s"     => \$args{dbname},
        "U|user=s"       => \$args{user},
        "w|no-password"  => \$args{no_password},
        "W|password"     => \$args{password},
        "conninfo=s"     => \$args{conninfo},
        "lookback=s"     => \$args{lookback},
        "max-chars=i"    => \$args{max_chars},
        "H|help"         => \$args{help},
    ) or die "Error in command line arguments\n";

    if ($args{help}) {
        print "Usage: $0 [options]\n";
        print "  -h, --host=HOST\n";
        print "  -p, --port=PORT\n";
        print "  -d, --dbname=DBNAME\n";
        print "  -U, --user=USER\n";
        print "  -w, --no-password\n";
        print "  -W, --password\n";
        print "      --conninfo=STRING\n";
        print "      --lookback=PERIOD  (default '6 months')\n";
        print "      --max-chars=NUM    (default 1000)\n";
        print "  -H, --help\n";
        exit 0;
    }

    my $host      = $args{host}     || $ENV{PGHOST}     || 'localhost';
    my $port      = $args{port}     || $ENV{PGPORT}     || 5432;
    my $dbname    = $args{dbname}   || $ENV{PGDATABASE} || 'postgres';
    my $user      = $args{user}     || $ENV{PGUSER}     || 'postgres';
    my $lookback  = $args{lookback} || '6 months';
    my $max_chars = defined $args{max_chars} ? $args{max_chars} : 1000;

    my $conninfo_or_params;
    if ($args{conninfo}) {
        $conninfo_or_params = $args{conninfo};
        if ($args{password}) {
            my $pw = prompt_for_password();
            $conninfo_or_params .= " password='$pw'";
        } elsif ($args{no_password}) {
            $conninfo_or_params .= " password=''";
        }
    } else {
        my $env_pass = $ENV{PGPASSWORD} || "";
        my $final_pass;
        if ($args{password}) {
            $final_pass = prompt_for_password();
        } elsif ($args{no_password}) {
            $final_pass = "";
        } else {
            $final_pass = $env_pass;
        }

        $conninfo_or_params = {
            host     => $host,
            port     => $port,
            dbname   => $dbname,
            user     => $user,
            password => $final_pass,
        };
    }

    my $results = fetch_and_chunk_logs($conninfo_or_params, $lookback, $max_chars);

    my $json = JSON::PP->new->canonical->pretty;
    print $json->encode($results);
}

main();
