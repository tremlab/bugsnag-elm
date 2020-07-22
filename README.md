# bugsnag-elm ![Build Status](https://travis-ci.org/NoRedInk/bugsnag-elm.svg?branch=master)

### What?
Log Elm "errors" to bugsnag 🐛

### Why?
The whole point of using Elm is to eliminate production errors.  So why would I need an error monitor? 🤷🏼‍♀️

Well, the world is still messy, and there may be bizarre edge cases that - while representing a possible state - are quite unpleasant for your user.  A service like bugsnag can help you report when these cases occur and track which are the most pernicious areas of your code.  You can also just log any activity you like. 👍

### How?
You'll need to [set up your own bugsnag account](https://app.bugsnag.com/user/new/) to get the example app working. There is a completely free tier which is great for side projects and just getting used to the tooling.

Once you have a bugsnag account, create a generic frontend JavaScript project in your dashboard, and copy its api key into the example app.

After you have successfully sent your first error report to bugsnag and got the hang of its dashboard, you can follow the example app's pattern to start adding bugsnag reports in your own project! 🎉

TLDR:

Install the package from your terminal:

      elm install tremlab/bugsnag-elm

Initialize bugsnag for your app:

      bugsnag = BugsnagElm.start
          { apiKey = "abcdef1234...."
          , appVersion = "xyz0101010......"
          , releaseStage = "test"
          , enabledReleaseStages = ["production", "staging", "test"]
          , user =
              Just
                  { id = "42"
                  , username = "Grace Hopper"
                  , email = "support@bugsnag.com"
                  }
          }

Use it!

      bugsnag.info
        "Hitting the slothNinja API."
        "PageCustomer.Login.Main"
        Dict.empty

      [ ( "Payload", toString payload ) ]
          |> Dict.fromList
          |> bugsnag.error
              "Unexpected payload from the slothNinja API."
              "Page.Customer.Login.Main"

Of course, this kind of side effect can only be triggered within an update function. If you are trying to capture a possible error state from anywhere else in your code, you may need to wrap that function's output in a `Result`, which can be bubbled up until the error can be sent from the update msg.

Although bugsnag does not officially support Elm, they have amazing [documentation](https://docs.bugsnag.com/) and support. ♥️ And of course, ask questions or offer suggestions here!

### Pattern
Although, underneath the hood, BugsnagElm constructs an HTTP POST request to send directly to bugnag's API, the package is modelled on the general syntax of a bugsnag notifier, so that it will be intuitive to switch between notifiers (you should use bugsnag on your backend too!) BugsnagElm currently follows bugsnag-js v7.0 syntax.

### Safety net
This package will only send handled "error" reports to bugsnag when you explicitly call it in your code. I would recommend also configuring [bugsnag-js](https://docs.bugsnag.com/platforms/javascript/) in your compiled elm JS code. This additional layer will catch any wacky, unhandled mayhem that may occur on your project.  (E.g. my team has noticed some browser extensions meddling with our Elm code.)

### Acknowledgements
This module was inspired by the [elm-rollbar](https://github.com/NoRedInk/elm-rollbar) module created by NoRedInk.  Many thanks to engineers there who provided feedback, guidance and code reviews on this module. Happy to report that all elm error traffic on their monolith now reports to bugsnag using bugsnag-elm. 💪
