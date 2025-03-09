# pgfarmlogs
This is a small command-line tool to extract error messages from the buildfarm logs. Since log files are often tens of megabytes
or more, we perform this parsing on the client side, streaming rows from the database. 

## Setup
This tool requires Python 3.8 or greater.

Create a virtual environment:
```
python3 -m venv .venv
```

Install dependencies:
```
pip install -r requirements.txt
```

## Run the tool
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