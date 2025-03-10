#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use DBI;
use JSON::PP;

use Getopt::Long qw(:config no_ignore_case);

# Magic delimiter, same as Python script
my $MAGIC = "==~_~===-=-===~_~==";

# ------------------------------------------------------------------------------
# chunk_log: Splits one large log string into an array of (filename, text_chunk).
# Mirroring the Python logic:
#   - The first chunk is labeled "head"
#   - Each subsequent chunk is preceded by <MAGIC>filename<MAGIC>
# ------------------------------------------------------------------------------
sub chunk_log {
    my ($log_text, $magic) = @_;
    my @chunks = ();
    my $current_filename = "head";
    my $pos = 0;

    while (1) {
        my $next_magic = index($log_text, $magic, $pos);
        if ($next_magic == -1) {
            # No more magic; everything from $pos to end is last chunk
            my $text_chunk = substr($log_text, $pos);
            push @chunks, [$current_filename, $text_chunk];
            last;
        }
        # The text before 'next_magic' is the chunk for the current filename
        my $text_chunk = substr($log_text, $pos, $next_magic - $pos);
        push @chunks, [$current_filename, $text_chunk];

        # Move past the magic delimiter
        $pos = $next_magic + length($magic);

        # Now read until the *next* magic to get the next filename
        my $next_magic2 = index($log_text, $magic, $pos);
        if ($next_magic2 == -1) {
            # If we never find the second magic, treat the rest as filename
            $current_filename = substr($log_text, $pos);
            # There's no text chunk after that, so we're done
            last;
        }
        $current_filename = substr($log_text, $pos, $next_magic2 - $pos);

        # Move 'pos' past this second magic
        $pos = $next_magic2 + length($magic);
    }

    return @chunks;  # array of arrayrefs: [ filename, text_chunk ]
}

# ------------------------------------------------------------------------------
# fetch_and_chunk_logs: Connect to Postgres, query rows, chunk their logs, return
# an array of parsed results. Each result is a hashref suitable for JSON output.
# ------------------------------------------------------------------------------
sub fetch_and_chunk_logs {
    my ($conninfo_or_params, $lookback, $max_chars) = @_;

    # Connect to Postgres
    my $dbh;
    if (ref($conninfo_or_params) eq 'HASH') {
        # We have a hash of connection params
        $dbh = DBI->connect(
            "dbi:Pg:dbname=$conninfo_or_params->{dbname};host=$conninfo_or_params->{host};port=$conninfo_or_params->{port}",
            $conninfo_or_params->{user},
            $conninfo_or_params->{password},
            {
                AutoCommit => 1,
                RaiseError => 1,
                PrintError => 0,
            }
        );
    } else {
        # We have a conninfo string
        # DBD::Pg can parse some connection info from "dbi:Pg:$conninfo"
        # but it's simpler to do "dbi:Pg:$conninfo" directly.
        my $conn_str = "dbi:Pg:$conninfo_or_params";
        $dbh = DBI->connect(
            $conn_str,
            undef,  # user
            undef,  # password
            {
                AutoCommit => 1,
                RaiseError => 1,
                PrintError => 0,
            }
        );
    }

    # Prepare and execute query
    my $sql = qq{
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
          AND snapshot > current_date - ?::interval
        ORDER BY snapshot ASC
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute($lookback);

    my @results;

    # Fetch row by row (should stream rather than read everything at once)
    while (my $row = $sth->fetchrow_hashref) {
        my $log_text = defined $row->{log} ? $row->{log} : "";

        # Break out the log into chunks
        my @pieces = chunk_log($log_text, $MAGIC);
        foreach my $piece (@pieces) {
            my ($filename, $text_section) = @$piece;

            # Keep only the last $max_chars characters
            if (length($text_section) > $max_chars) {
                $text_section = substr($text_section, -1 * $max_chars);
            }

            push @results, {
                sysname  => $row->{sysname},
                snapshot => "$row->{snapshot}", # stringified
                status   => $row->{status},
                stage    => $row->{stage},
                filename => $filename =~ s/^\s+|\s+$//gr, # strip spaces
                commit   => $row->{commit},
                branch   => $row->{branch},
                text     => $text_section,
            };
        }
    }

    $sth->finish;
    $dbh->disconnect;

    return \@results;
}

# ------------------------------------------------------------------------------
# prompt_for_password
# ------------------------------------------------------------------------------
sub prompt_for_password {
    print "Password: ";
    my $pw = <STDIN>;
    chomp($pw);
    return $pw;
}

# ------------------------------------------------------------------------------
# main: parse CLI args (psql-like), figure out password logic, call fetch logic
# ------------------------------------------------------------------------------
sub main {
    my %args;
    GetOptions(
        # psql-style short options
        "h|host=s"    => \$args{host},
        "p|port=i"    => \$args{port},
        "d|dbname=s"  => \$args{dbname},
        "U|user=s"    => \$args{user},

        # approximate psql -w / -W
        "w|no-password" => \$args{no_password},
        "W|password"    => \$args{password},

        # optional full connection info
        "conninfo=s"  => \$args{conninfo},

        # additional filter params
        "lookback=s"  => \$args{lookback},
        "max-chars=i" => \$args{max_chars},

        # help
        "H|help"      => \$args{help},
    ) or die "Error in command line arguments\n";

    if ($args{help}) {
        print "Usage: $0 [options]\n";
        print "  -h, --host=HOST         Database server host (default from \$PGHOST or 'localhost')\n";
        print "  -p, --port=PORT         Database server port (default from \$PGPORT or 5432)\n";
        print "  -d, --dbname=DBNAME     Database name (default from \$PGDATABASE or 'postgres')\n";
        print "  -U, --user=USER         Database user (default from \$PGUSER or 'postgres')\n";
        print "  -w, --no-password       Never prompt for password. (Sets empty password)\n";
        print "  -W, --password          Prompt for password, ignoring \$PGPASSWORD.\n";
        print "      --conninfo=STRING   Full libpq connection string (e.g. 'host=... port=... dbname=... user=...')\n";
        print "      --lookback=PERIOD   PostgreSQL interval syntax (e.g. '2 days'); default '6 months'\n";
        print "      --max-chars=NUM     Number of chars from end of each chunk; default 1000.\n";
        print "  -H, --help              Show this help message.\n";
        exit 0;
    }

    # Default values (like python script)
    my $host     = $args{host}     || $ENV{PGHOST}     || 'localhost';
    my $port     = $args{port}     || $ENV{PGPORT}     || 5432;
    my $dbname   = $args{dbname}   || $ENV{PGDATABASE} || 'postgres';
    my $user     = $args{user}     || $ENV{PGUSER}     || 'postgres';
    my $lookback = $args{lookback} || '6 months';
    my $max_chars= defined $args{max_chars} ? $args{max_chars} : 1000;

    my $conninfo_or_params;
    if ($args{conninfo}) {
        # They provided a direct conninfo string
        $conninfo_or_params = $args{conninfo};

        if ($args{password}) {
            my $pw = prompt_for_password();
            # Append or override password=... in the conninfo
            $conninfo_or_params .= " password='$pw'";
        } elsif ($args{no_password}) {
            # Force empty password
            $conninfo_or_params .= " password=''";
        }
    } else {
        # Build a connection params hash
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

    # Fetch and chunk
    my $results = fetch_and_chunk_logs($conninfo_or_params, $lookback, $max_chars);

    # Convert to JSON (pretty print)
    my $json = JSON::PP->new->canonical->pretty;
    print $json->encode($results);
}

main();
