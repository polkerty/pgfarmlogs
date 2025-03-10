# pgfarmlogs
This is a small command-line tool to extract error messages from the buildfarm logs. Since log files are often tens of megabytes
or more, we perform this parsing on the client side, streaming rows from the database. 

There are rouughly equivalent python and perl scripts. 

## Perl

### Setup
This script was tested on Perl 5 on MacOS. It requires the DBI and DBD::Pg modules, which you may need to install if not 
already availabe.

## Run the tool

```
python main.pl [connection options] [--lookback "2 weeks"]
```

You will need to provide some connection options, similar to psql style, to tell the script how to connect to your database.
You can also optionally provide a lookback parameter with is passed as an interval to the SQL query; it could be "2 weeks", or "3 months",
etc.

Here's an example of how I run the script on my computer:

```
perl main.pl -p 6565 -d farm -u jbrazeal --lookback '4 days'
```

You can run `perl main.pl --help` to see the CLI options:

```
Usage: main.pl [options]
  -h, --host=HOST         Database server host (default from $PGHOST or 'localhost')
  -p, --port=PORT         Database server port (default from $PGPORT or 5432)
  -d, --dbname=DBNAME     Database name (default from $PGDATABASE or 'postgres')
  -U, --user=USER         Database user (default from $PGUSER or 'postgres')
  -w, --no-password       Never prompt for password. (Sets empty password)
  -W, --password          Prompt for password, ignoring $PGPASSWORD.
      --conninfo=STRING   Full libpq connection string (e.g. 'host=... port=... dbname=... user=...')
      --lookback=PERIOD   PostgreSQL interval syntax (e.g. '2 days'); default '6 months'
      --max-chars=NUM     Number of chars from end of each chunk; default 1000.
  -H, --help              Show this help message.
  ```
  
## Python

### Setup
This tool requires Python 3.8 or greater.

Create a virtual environment:
```
python3 -m venv .venv
```

Install dependencies:
```
pip install -r requirements.txt
```

### Run the tool
You just need to tell the tool where the database lives. It uses connection arguments/environment variables similar to psql. 
For example, my test database is on localhost using my default user
at port 6565 and no password, so I can run:

```
python main.py -p 6565 -d farm
```

You can run `python main.py --help` to see possible options.

The tool runs the following query:

```
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
    AND snapshot > current_date - %s::interval
ORDER BY snapshot ASC
```

It streams the results row-by-row and outputs a JSON array containing the last 1000 characters 
of each file with a given log. The lookback period is configurable (defaults to 6 months). The number of characters
from each file is also configurable. 