module BugsnagElm exposing
    ( BugsnagClient, BugsnagConfig, User, Severity(..)
    , start, notify
    )

{-| Send error reports to bugsnag.


## Types

@docs BugsnagClient, BugsnagConfig, User, Severity


## Types

@docs start, notify

-}

import Dict exposing (Dict)
import Http
import Json.Encode as Encode exposing (Value)
import Task exposing (Task)


{-| Functions preapplied with access tokens, scopes, and releaseStages,
separated by [`Severity`](#Severity).

Create one using [`start`](#start).

-}
type alias BugsnagClient =
    { error : String -> Dict String Value -> Task Http.Error ()
    , warning : String -> Dict String Value -> Task Http.Error ()
    , info : String -> Dict String Value -> Task Http.Error ()
    }


{-| Basic data needed to define the local client for a BugsnagElm instance.
Applies to all error reports that may occur on the page,
with error-specific data added later in `notify`

  - `token` - The [Bugsnag API token](https://Bugsnag.com/docs/api/#authentication) required to authenticate the request.
  - codeVersion -
  - `context` - Scoping messages essentially namespaces them. For example, this might be the name of the page the user was on when the message was sent.
  - `releaseStage` - usually `"production"`, `"development"`, `"staging"`, etc., but bugsnag accepts any value
  - `enabledReleaseStages` - explictly define which stages you want to report, omitting any you'd prefer to simply log in console (e.g. "dev"). Empty list will report ALL error stages.
  - 'user' - if available, report default user data (id, name, email)

-}
type alias BugsnagConfig =
    { token : String
    , codeVersion : String
    , context : String
    , releaseStage : String
    , enabledReleaseStages : List String
    , user : Maybe User
    }


{-| Severity levels - bugsnag only accepts these three.
-}
type Severity
    = Error
    | Warning
    | Info


{-| A record of datapoints bugsnag's api can accept for user data.
To display additional custom user data alongside these standard fields on the Bugsnag website,
the custom data should be included in the 'metaData' object in a `user` object.
-}
type alias User =
    { id : String
    , username : String
    , email : String
    }


{-| Return a [`Bugsnag`](#Bugsnag) record configured with the given
[`Environment`](#Environment) and [`Scope`](#Scope) string.

    Bugsnag = Bugsnag.start "Page/Home.elm"

    Bugsnag.debug "Hitting the hats API." Dict.empty

    [ ( "Payload", toString payload ) ]
        |> Dict.fromList
        |> Bugsnag.error "Unexpected payload from the hats API."

-}
start : BugsnagConfig -> BugsnagClient
start bugsnagConfig =
    { error = notify bugsnagConfig Error
    , warning = notify bugsnagConfig Warning
    , info = notify bugsnagConfig Info
    }


{-| Send a message to bugsnag. [`start`](#start)
provides a nice wrapper around this.

Arguments:

  - `BugsnagConfig`
  - `Severity` - severity, e.g. `Error`, `Warning`, `Debug`
  - `String` - message, e.g. "Auth server was down when user tried to sign in."
  - `Dict String Value` - arbitrary metaData, e.g. \`{"accountType": "premium"}

If the message was successfully sent to Bugsnag

Otherwise it fails
with the [`Http.Error`](http://package.elm-lang.org/packages/elm-lang/http/latest/Http#Error)
responsible.

-}
notify : BugsnagConfig -> Severity -> String -> Dict String Value -> Task Http.Error ()
notify bugsnagConfig severity message metaData =
    let
        body : Http.Body
        body =
            toJsonBody bugsnagConfig severity message metaData

        shouldSend =
            List.isEmpty bugsnagConfig.notifyReleaseStages
                || List.member bugsnagConfig.releaseStage bugsnagConfig.notifyReleaseStages
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
While there are many restrictions, note that `metaData`
can include any key/value pairs (including nested) you'd like to report.
See <https://bugsnag.com/docs/api/items_post/> for schema
-}
toJsonBody :
    BugsnagConfig
    -> Severity
    -> String
    -> Dict String Value
    -> Http.Body
toJsonBody bugsnagConfig severity message metaData =
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
                 , ( "context", Encode.string bugsnagConfig.context )
                 , ( "severity", Encode.string (severityToString severity) )
                 , ( "metaData"
                   , metaData
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
