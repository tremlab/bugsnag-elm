# Example app for bugsnag-elm

### To get this example app running locally:

- Make sure Elm is installed in your local environment: [Install Elm](https://guide.elm-lang.org/install/elm.html)

- replace the placeholder API key in `Example.elm` with your own bugsnag API key (Bugsnag doesn't formally support Elm, so create a generic JS project [here](https://app.bugsnag.com), then grab its API key.)

- from the local `/example` directory, run: `elm reactor` and visit the local site it generates

- from there, click into `Example.elm` and then you'll be in the app itself!

- type any message into the field and submit.  You should, within seconds, be see a new error event, with that name, show up in your bugsnag dashbaord. 🎉
