module BugsnagElm exposing
    ( Bugsnag, BugsnagConfig, User, Severity(..)
    , start, notify
    )

{-| Send error reports to bugsnag.

### General example

    import BugsnagElm exposing (Bugsnag)
    import Task exposing (Task)

    -- initialize bugsnag. You will probably need to pull values from the env or flags
    bugsnag : Bugsnag
    bugsnug =
        BugsnagElm.start
            { token = "abcdef1234...."
            , codeVersion = "xyz0101010......"
            , releaseStage = "test"
            , enabledReleaseStages = ["production", "staging", "test"]
            , user =
                Just
                    { id = flags.currentUserId
                    , username = flags.username
                    , email = flags.email
                    }
            }

    -- send error reports within your app's update function
    update msg model =
        .... ->
            -- log some debug info
            ( model
            , bugsnag.info
                "Hitting the slothNinja API."
                "Page.Customer.Login.Main"
                Dict.empty
                |> Task.attempt (\() -> NoOp) -- convert the Task into a Cmd
            )

        .... ->
            -- log an error
            ( model
            , [ ( "Payload", toString payload ) ]
                |> Dict.fromList
                |> bugsnag.error
                    "Unexpected payload from the slothNinja API."
                    "Page.Customer.Login.Main"
                |> Task.attempt (\() -> NoOp) -- convert the Task into a Cmd
            )


## Basic Usage

@docs start, Bugsnag, BugsnagConfig, User, Severity

## Customized Usage
@docs notify


-}

import Dict exposing (Dict)
import Http
import Json.Encode as Encode exposing (Value)
import Task exposing (Task)


{-| Functions preapplied with access token, code version, user info and releaseStage,
separated by [`Severity`](#Severity).

Create one using [`start`](#start), and then throughout your app you can call `bugsnag.error` to send the error report.

When calling any of the functions herein, it will return `Task.succeed ()` if the message was successfully sent to Bugsnag. Otherwise it fails with the [`Http.Error`](http://package.elm-lang.org/packages/elm-lang/http/latest/Http#Error)
responsible. I recommend you ignore the error in your code; although it is possible for the bugsnag api to go down, it is exceedingly rare, and not something worth disrupting your user's experience for.

        bugsnag.error "problem accessing the database." "Page.Checkout" Dict.empty
            |> Task.attempt (\() -> NoOp) -- convert the Task into a Cmd


-}
type alias Bugsnag =
    { error : String -> String ->  Dict String Value -> Task Http.Error ()
    , warning : String -> String ->  Dict String Value -> Task Http.Error ()
    , info : String -> String ->  Dict String Value -> Task Http.Error ()
    }


{-| Basic data needed to define the local client for a BugsnagElm instance.
Applies to all error reports that may occur in the app,
with error-specific data added later in `notify`

  - `token` - The [Bugsnag API token](https://Bugsnag.com/docs/api/#authentication) required to authenticate the request.
  - `codeVersion` - However your app identifies its versions, include it here as a string
  - `releaseStage` - usually `"production"`, `"development"`, `"staging"`, etc., but bugsnag accepts any value
  - `enabledReleaseStages` - explictly define which stages you want to report, omitting any you'd prefer to drop (e.g. "development"). Empty list will report ALL error stages.
  - `user` - if available, report default user data (id, name, email)

-}
type alias BugsnagConfig =
    { token : String
    , codeVersion : String
    , releaseStage : String
    , enabledReleaseStages : List String
    , user : Maybe User
    }


{-| Severity levels - bugsnag only accepts [these three](https://docs.bugsnag.com/product/severity-indicator/#severity).
-}
type Severity
    = Error
    | Warning
    | Info


{-| A record of datapoints bugsnag's api can accept for user data.
To display additional custom user data alongside these standard fields on the Bugsnag website,
the custom data should be included in the 'metadata' object in a `user` object.
[learn more](https://docs.bugsnag.com/platforms/javascript/#identifying-users)
-}
type alias User =
    { id : String
    , username : String
    , email : String
    }


{-| Return a [`Bugsnag`](#Bugsnag) record configured with the given BugsnagConfig details.

    bugsnag = BugsnagElm.start
        { token = "abcdef1234...."
        , codeVersion = "xyz0101010......"
        , releaseStage = "test"
        , enabledReleaseStages = ["production", "staging", "test"]
        , user =
            Just
                { id = "42"
                , username = "Grace Hopper"
                , email = "support@bugsnag.com"
                }
        }

-}
start : BugsnagConfig -> Bugsnag
start bugsnagConfig =
    { error = notify bugsnagConfig Error
    , warning = notify bugsnagConfig Warning
    , info = notify bugsnagConfig Info
    }


{-| Send a message to bugsnag. [`start`](#start)
provides a nice wrapper around this.

Arguments:

  - `BugsnagConfig`
  - `Severity` - severity, one of: `Error`, `Warning`, or `Info`
  - `String` - message, e.g. "Auth server was down when user tried to sign in."
  - `String` - context, where the error occurred e.g. module or file name "Page.Customer.Login.Main"
  - `Dict String Value` - arbitrary metadata, e.g. `{"accountType": "premium", "region": "NW"}

If the message was successfully sent to Bugsnag, it returns `Task.succeed ()` Otherwise it fails with the [`Http.Error`](http://package.elm-lang.org/packages/elm-lang/http/latest/Http#Error)
responsible. I recommend you ignore this error in your code; although it is possible for the bugsnag api to go down, it is exceedingly rare, and not something worth disrupting your user's experience for.

    notify bugsnagConfig Error "cannot connect to database" "Page.Login" Dict.empty

-}
notify : BugsnagConfig -> Severity -> String -> String -> Dict String Value -> Task Http.Error ()
notify bugsnagConfig severity message context metadata =
    let
        body : Http.Body
        body =
            toJsonBody bugsnagConfig severity message context metadata

        shouldSend =
            List.isEmpty bugsnagConfig.enabledReleaseStages
                || List.member bugsnagConfig.releaseStage bugsnagConfig.enabledReleaseStages
    in
    case shouldSend of
        True ->
            { method = "POST"
            , headers =
                [ Http.header "Bugsnag-Api-Key" bugsnagConfig.token
                , Http.header "Bugsnag-Payload-Version" "5"
                ]
            , url = endpointUrl
            , body = body
            , resolver = Http.stringResolver resolveNotify
            , timeout = Nothing
            }
                |> Http.task

        False ->
            Task.succeed ()



-- INTERNAL --


resolveNotify : Http.Response String -> Result Http.Error ()
resolveNotify response =
    case response of
        Http.BadUrl_ url ->
            Err (Http.BadUrl url)

        Http.Timeout_ ->
            Err Http.Timeout

        Http.NetworkError_ ->
            Err Http.NetworkError

        Http.BadStatus_ metadata body ->
            Err (Http.BadStatus metadata.statusCode)

        Http.GoodStatus_ _ _ ->
            Ok ()


severityToString : Severity -> String
severityToString report =
    case report of
        Error ->
            "error"

        Info ->
            "info"

        Warning ->
            "warning"


bugsnagElmVersion =
    "1.0.0"


{-| Format all datapoints into JSON for bugsnag's api.
While there are many restrictions, note that `metadata`
can include any key/value pairs (including nested) you'd like to report.
See <https://bugsnag.com/docs/api/items_post/> for full schema details.
-}
toJsonBody :
    BugsnagConfig
    -> Severity
    -> String
    -> String
    -> Dict String Value
    -> Http.Body
toJsonBody bugsnagConfig severity message context metadata =
    let
        userInfo =
            case bugsnagConfig.user of
                Just user ->
                    [ ( "user"
                      , Encode.object
                            [ ( "id", Encode.string user.id )
                            , ( "name", Encode.string user.username )
                            , ( "email", Encode.string user.email )
                            ]
                      )
                    ]

                Nothing ->
                    []
    in
    [ ( "payloadVersion", Encode.string "5" )
    , ( "notifier"
      , Encode.object
            [ ( "name", Encode.string "bugsnag-elm" )
            , ( "version", Encode.string bugsnagElmVersion )
            , ( "url", Encode.string "https://github.com/noredink/bugsnag-elm" )
            ]
      )
    , ( "events"
      , Encode.list identity
            [ Encode.object
                ([ ( "exceptions"
                   , Encode.list identity
                        [ Encode.object
                            [ ( "errorClass", Encode.string message )

                            -- , ( "message", Encode.string message ) -- TODO: useful data to report here?
                            , ( "stacktrace", Encode.list identity [] )
                            ]
                        ]
                   )
                 , ( "context", Encode.string context )
                 , ( "severity", Encode.string (severityToString severity) )
                 , ( "metadata"
                   , metadata
                        |> Encode.dict identity identity
                   )
                 , ( "app"
                   , Encode.object
                        [ ( "version", Encode.string bugsnagConfig.codeVersion )
                        , ( "releaseStage", Encode.string bugsnagConfig.releaseStage )
                        , ( "type", Encode.string "elm" )
                        ]
                   )
                 ]
                    ++ userInfo
                )
            ]
      )
    ]
        |> Encode.object
        |> Http.jsonBody


endpointUrl : String
endpointUrl =
    "https://notify.bugsnag.com"
