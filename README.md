# bugsnag-elm ![Build Status](https://travis-ci.org/NoRedInk/bugsnag-elm.svg?branch=master)

Send error reports to bugsnag.

### Development

- Before publishing changes you must make sure that the value of `Bugsnag.Internal.version` matches the `version` in elm.json. The script `scripts/verify-notifier-version.sh` will check this for you and also fail the Travis build.
