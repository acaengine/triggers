# PlaceOS Triggers

[![Build Status](https://travis-ci.org/placeos/triggers.svg?branch=master)](https://travis-ci.org/placeos/triggers)

PlaceOS service handling events and conditional triggers.

## Testing

`crystal spec`

## Compiling

`shards build`

## Deploying

Once compiled you are left with a binary `triggers`

* for help `./triggers --help`
* viewing routes `./triggers --routes`
* run on a different port or host `./triggers -b 0.0.0.0 -p 80`
