# Online-Beratung Release

### Getting started


#### Command parameters

`-m` Enable auto merge 

`-b` Branch to release (staging, release) 

`-t` Release tag (YYYY-mm-dd) e.g. 2022-12-01

`-v` Enable verbose mode

`-i` Init release branch if it does not exist already

`-g` Pass github token if not defined in environment variable GH_TOKEN

`-h` Show command help

#### Environment variables
`GH_TOKEN`:
Configure github token to use for push/merge commands

`TEAMS_WEBHOOK_URL`:
Configure a teams webhook url for notification if new changes were merged or pull requests are opened



