module Bugsnag exposing
    ( Severity(..)
    , scoped, send
    , BugsnagClient, BugsnagConfig, User
    )

{-| Send error reports to bugsnag.


## Types

@docs BugsnagClient, BugsnagConfig, User, Severity


## Types

@docs scoped, send

-}

import Bugsnag.Internal
import Dict exposing (Dict)
import Http
import Json.Encode as Encode exposing (Value)
import Task exposing (Task)
import Time exposing (Posix)


{-| Functions preapplied with access tokens, scopes, and environments,
separated by [`Severity`](#Severity).

Create one using [`scoped`](#scoped).

-}
type alias BugsnagClient =
    { error : String -> Dict String Value -> Task Http.Error (Dict String Value)
    , warning : String -> Dict String Value -> Task Http.Error (Dict String Value)
    , info : String -> Dict String Value -> Task Http.Error (Dict String Value)
    }


{-| Basic data needed to define the local client for a Bugsnag instance.
Applies to all error reports that may occurr on the page,
with error-specific data added later in `send`

  - `token` - The [Bugsnag API token](https://Bugsnag.com/docs/api/#authentication) required to authenticate the request.
  - codeVersion -
  - `context` - Scoping messages essentially namespaces them. For example, this might be the name of the page the user was on when the message was sent.
  - `environment` - usually `"production"`, `"development"`, `"staging"`, etc., but bugsnag accepts any value
  - 'user' - if available, report default user data (id, name, email)

-}
type alias BugsnagConfig =
    { token : String
    , codeVersion : String
    , context : String
    , environment : String
    , user : Maybe User
    }


{-| Severity levels - Bugsnag only accepts these three.
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


{-| Send a message to Bugsnag. [`scoped`](#scoped)
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
send : BugsnagConfig -> Severity -> String -> Dict String Value -> Task Http.Error (Dict String Value)
send bugsnagConfig severity message metaData =
    Time.now
        |> Task.andThen (sendWithTime bugsnagConfig severity message metaData)



-- INTERNAL --


severityToString : Severity -> String
severityToString report =
    case report of
        Error ->
            "error"

        Info ->
            "info"

        Warning ->
            "warning"


sendWithTime :
    BugsnagConfig
    -> Severity
    -> String
    -> Dict String Value
    -> Posix
    -> Task Http.Error (Dict String Value)
sendWithTime bugsnagConfig severity message metaData time =
    let
        body : Http.Body
        body =
            toJsonBody bugsnagConfig severity message metaData
    in
    { method = "POST"
    , headers =
        [ Http.header "Bugsnag-Api-Key" bugsnagConfig.token
        , Http.header "Bugsnag-Payload-Version" "5"
        ]
    , url = endpointUrl
    , body = body
    , resolver = Http.stringResolver (\_ -> Ok ()) -- TODO
    , timeout = Nothing
    }
        |> Http.task
        |> Task.map (\() -> metaData)


{-| Format all datapoints into JSON for Bugsnag's api.
While there are many restrictions, note that `metaData`
can include any key/value pairs (including nested) you'd like to report.
See <https://Bugsnag.com/docs/api/items_post/> for schema
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
            , ( "version", Encode.string Bugsnag.Internal.version )
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
                        , ( "releaseStage", Encode.string bugsnagConfig.environment )
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


{-| Return a [`Bugsnag`](#Bugsnag) record configured with the given
[`Environment`](#Environment) and [`Scope`](#Scope) string.

    Bugsnag = Bugsnag.scoped "Page/Home.elm"

    Bugsnag.debug "Hitting the hats API." Dict.empty

    [ ( "Payload", toString payload ) ]
        |> Dict.fromList
        |> Bugsnag.error "Unexpected payload from the hats API."

-}
scoped : BugsnagConfig -> BugsnagClient
scoped bugsnagConfig =
    { error = send bugsnagConfig Error
    , warning = send bugsnagConfig Warning
    , info = send bugsnagConfig Info
    }


endpointUrl : String
endpointUrl =
    "https://notify.bugsnag.com"
