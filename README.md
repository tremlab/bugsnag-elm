# bugsnag-elm ![Build Status](https://travis-ci.org/NoRedInk/bugsnag-elm.svg?branch=master)

### What?
Log Elm "errors" to bugsnag.

### Why?
The whole point of using Elm is to eliminate production errors.  So why would I need an error monitor? 🤷🏼‍♀️

Well, the world is still messy, and there may be bizarre edge cases that - while representing a possible state - are quite unpleasant for your user.  A service like bugsnag can help you report when these cases occur and track which are the most pernicious areas of your code.  You can also just log any activity you like. 👍

This package will only send handled "error" reports to bugsnag when you explicitly call it in your code. I would recommend also configuring [bugsnag-js](https://docs.bugsnag.com/platforms/javascript/) in your compiled elm JS code. This additional layer will catch any wacky, unhandled mayhem that may occur on your project.  (E.g. my team has noticed some browser extensions meddling with our Elm code.)

### How?
You'll need to [set up your own bugsnag account](https://app.bugsnag.com/user/new/) to get the example app working. There is a completely free tier which is great for side projects and just getting used to the tooling.

Once you have an account, create a generic frontend JavaScript project, and copy that api key into the example app.

After you have successfully sent your first error report to bugsnag and got the hang of the dashboard, you can follow the example app's pattern to start adding bugsnag reports in your own project! 🎉

Although bugsnag does not officially support Elm, they have amazing [documentation](https://docs.bugsnag.com/) and support. ♥️ And of course, ask questions or offer suggestions here!

### Pattern
Although, underneath the hood, BugsnagElm constructs an HTTP POST to send directly to bugnag's API, the package is modelled on the general syntax of a bugsnag notifier, so that it will be intuitive to switch between notifiers (you should use bugsnag on your backend too!) BugsnagElm follows bugsnag-js v7.0 syntax.


### Development

- Before publishing changes you must make sure that the value of `Bugsnag.Internal.version` matches the `version` in elm.json. The script `scripts/verify-notifier-version.sh` will check this for you and also fail the Travis build.
