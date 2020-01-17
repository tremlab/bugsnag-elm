module Bugsnag exposing
    ( Bugsnag, Level(..), Token, token, Environment, environment, Scope, scope, CodeVersion, codeVersion
    , scoped, send
    )

{-| Send error reports to bugsnag.


## Types

@docs Bugsnag, Level, Token, token, Environment, environment, Scope, scope, CodeVersion, codeVersion


## Types

@docs scoped, send

-}

import Bitwise
import Bugsnag.Internal
import Dict exposing (Dict)
import Http
import Json.Encode as Encode exposing (Value)
import Murmur3
import Process
import Random
import Task exposing (Task)
import Time exposing (Posix)
import Uuid exposing (Uuid, uuidGenerator)


{-| Functions preapplied with access tokens, scopes, and environments,
separated by [`Level`](#Level).

Create one using [`scoped`](#scoped).

-}
type alias Bugsnag =
    { error : String -> Dict String Value -> Task Http.Error Uuid
    , warning : String -> Dict String Value -> Task Http.Error Uuid
    , info : String -> Dict String Value -> Task Http.Error Uuid
    }


{-| Severity levels.
-}
type Level
    = Error
    | Warning
    | Info


{-| A Bugsnag API access token.

Create one using [`token`](#token).

    Bugsnag.token "12c99de67a444c229fca100e0967486f"

-}
type Token
    = Token String


{-| A scope, for example `"login"`.

Create one using [`scope`](#scope).

    Bugsnag.scope "login"

-}
type Scope
    = Scope String


{-| A code version, for example - a git commit hash.

Create one using [`codeVersion`](#codeVersion).

    Bugsnag.codeVersion "24dcf3a9a9cf1a5e2ea319018644a68f4743a731"

-}
type CodeVersion
    = CodeVersion String


{-| Create a [`Scope`](#Scope).

    Bugsnag.scope "login"

-}
scope : String -> Scope
scope =
    Scope


{-| Create a [`CodeVersion`](#CodeVersion).

    Bugsnag.codeVersion "24dcf3a9a9cf1a5e2ea319018644a68f4743a731"

-}
codeVersion : String -> CodeVersion
codeVersion =
    CodeVersion


{-| For example, "production", "development", or "staging".

Create one using [`environment`](#environment).

    Bugsnag.environment "production"

-}
type Environment
    = Environment String


{-| Create a [`Token`](#token)

    Bugsnag.token "12c99de67a444c229fca100e0967486f"

-}
token : String -> Token
token =
    Token


{-| Create an [`Environment`](#Environment)

    Bugsnag.environment "production"

-}
environment : String -> Environment
environment =
    Environment


{-| Send a message to Bugsnag. [`scoped`](#scoped)
provides a nice wrapper around this.

Arguments:

  - `Token` - The [Bugsnag API token](https://Bugsnag.com/docs/api/#authentication) required to authenticate the request.
  - `Scope` - Scoping messages essentially namespaces them. For example, this might be the name of the page the user was on when the message was sent.
  - `Environment` - e.g. `"production"`, `"development"`, `"staging"`, etc.
  - `Int` - maximum retry attempts - if the response is that the message was rate limited, try resending again (once per second) up to this many times. (0 means "do not retry.")
  - `Level` - severity, e.g. `Error`, `Warning`, `Debug`
  - `String` - message, e.g. "Auth server was down when user tried to sign in."
  - `Dict String Value` - arbitrary metadata, e.g. `{"username": "rtfeldman"}`

If the message was successfully sent to Bugsnag, the [`Task`](http://package.elm-lang.org/packages/elm-lang/core/latest/Task#Task)
succeeds with the [`Uuid`](http://package.elm-lang.org/packages/danyx23/elm-uuid/latest/Uuid#Uuid)
it generated and sent to Bugsnag to identify the message. Otherwise it fails
with the [`Http.Error`](http://package.elm-lang.org/packages/elm-lang/http/latest/Http#Error)
responsible.

-}
send : Token -> CodeVersion -> Scope -> Environment -> Int -> Level -> String -> Dict String Value -> Task Http.Error Uuid
send vtoken vcodeVersion vscope venvironment maxRetryAttempts level message metadata =
    Time.now
        |> Task.andThen (sendWithTime vtoken vcodeVersion vscope venvironment maxRetryAttempts level message metadata)



-- INTERNAL --


levelToString : Level -> String
levelToString report =
    case report of
        Error ->
            "error"

        Info ->
            "info"

        Warning ->
            "warning"


sendWithTime : Token -> CodeVersion -> Scope -> Environment -> Int -> Level -> String -> Dict String Value -> Posix -> Task Http.Error Uuid
sendWithTime vtoken vcodeVersion vscope venvironment maxRetryAttempts level message metadata time =
    let
        uuid : Uuid
        uuid =
            uuidFrom vtoken vscope venvironment level message metadata time

        body : Http.Body
        body =
            toJsonBody vtoken vscope vcodeVersion venvironment level message uuid metadata
    in
    { method = "POST"
    , headers =
        [ tokenHeader vtoken

        -- , content-type application/json
        -- , Bugsnag-Payload-Version 5
        --         HEADERS
        -- Content-Type:application/json
        -- Bugsnag-Api-Key:YOUR-NOTIFIER-API-KEY - The API Key associated with the project. Informs Bugsnag which project has generated this error.
        -- Bugsnag-Payload-Version:5 - The version number of the payload. Must be set to `5`.
        -- Bugsnag-Sent-At:2018-01-01T15:00:00.000Z - The time (in ISO 8601 format) that the event payload is being sent. This is only required when sending session details in the event payload. It is used to ensure that the reported session start times are standardized across reporting devices.
        ]
    , url = endpointUrl
    , body = body
    , resolver = Http.stringResolver (\_ -> Ok ()) -- TODO
    , timeout = Nothing
    }
        |> Http.task
        |> Task.map (\() -> uuid)
        |> withRetry maxRetryAttempts


withRetry : Int -> Task Http.Error a -> Task Http.Error a
withRetry maxRetryAttempts task =
    let
        retry : Http.Error -> Task Http.Error a
        retry httpError =
            if maxRetryAttempts > 0 then
                case httpError of
                    Http.BadStatus statusCode ->
                        if statusCode == 429 then
                            -- Wait a bit between retries.
                            Process.sleep (Time.posixToMillis retries.msDelayBetweenRetries |> toFloat)
                                |> Task.andThen (\() -> withRetry (maxRetryAttempts - 1) task)

                        else
                            Task.fail httpError

                    _ ->
                        Task.fail httpError

            else
                Task.fail httpError
    in
    Task.onError retry task


{-| Using the current system time as a random number seed generator, generate a
UUID.

We could theoretically generate the same UUID twice if we tried to send
two messages in extremely rapid succession. To guard against this, we
incorporate the contents of the message in the random number seed so that the
only way we could expect the same UUID is if we were sending a duplicate
message.

-}
uuidFrom : Token -> Scope -> Environment -> Level -> String -> Dict String Value -> Posix -> Uuid
uuidFrom (Token vtoken) (Scope vscope) (Environment venvironment) level message metadata time =
    let
        ms =
            Time.posixToMillis time

        hash : Int
        hash =
            [ Encode.string (levelToString level)
            , Encode.string message
            , Encode.string vtoken
            , Encode.string vscope
            , Encode.string venvironment
            , Encode.dict identity identity metadata
            ]
                |> Encode.list identity
                |> Encode.encode 0
                |> Murmur3.hashString ms

        combinedSeed =
            Bitwise.xor (floor (ms |> toFloat)) hash
    in
    Random.initialSeed combinedSeed
        |> Random.step uuidGenerator
        |> Tuple.first


toJsonBody : Token -> Scope -> CodeVersion -> Environment -> Level -> String -> Uuid -> Dict String Value -> Http.Body
toJsonBody (Token vtoken) (Scope vscope) (CodeVersion vcodeVersion) (Environment venvironment) level message uuid metadata =
    -- See https://Bugsnag.com/docs/api/items_post/ for schema
    [ ( "access_token", Encode.string vtoken )
    , ( "data"
      , Encode.object
            [ ( "environment", Encode.string venvironment )
            , ( "context", Encode.string vscope )
            , ( "uuid", Uuid.encode uuid )
            , ( "client"
              , Encode.object
                    [ ( "elm"
                      , Encode.object
                            [ ( "code_version", Encode.string vcodeVersion ) ]
                      )
                    ]
              )
            , ( "notifier"
              , Encode.object
                    [ ( "name", Encode.string "elm-Bugsnag" )
                    , ( "version", Encode.string Bugsnag.Internal.version )
                    ]
              )
            , ( "level", Encode.string (levelToString level) )
            , ( "endpoint", Encode.string endpointUrl )
            , ( "platform", Encode.string "browser" )
            , ( "language", Encode.string "Elm" )
            , ( "body"
              , Encode.object
                    [ ( "message"
                      , Encode.object
                            (( "body", Encode.string message ) :: Dict.toList metadata)
                      )
                    ]
              )
            ]
      )
    ]
        |> Encode.object
        |> Http.jsonBody


tokenHeader : Token -> Http.Header
tokenHeader (Token vtoken) =
    Http.header "X-Bugsnag-Access-Token" vtoken


{-| Return a [`Bugsnag`](#Bugsnag) record configured with the given
[`Environment`](#Environment) and [`Scope`](#Scope) string.

If the HTTP request to Bugsnag fails because of an exceeded rate limit (status
code 429), this will retry the HTTP request once per second, up to 60 times.

    Bugsnag = Bugsnag.scoped "Page/Home.elm"

    Bugsnag.debug "Hitting the hats API." Dict.empty

    [ ( "Payload", toString payload ) ]
        |> Dict.fromList
        |> Bugsnag.error "Unexpected payload from the hats API."

-}
scoped : Token -> CodeVersion -> Environment -> String -> Bugsnag
scoped vtoken vcodeVersion venvironment scopeStr =
    let
        vscope =
            Scope scopeStr
    in
    { error = send vtoken vcodeVersion vscope venvironment retries.defaultMaxAttempts Error
    , warning = send vtoken vcodeVersion vscope venvironment retries.defaultMaxAttempts Warning
    , info = send vtoken vcodeVersion vscope venvironment retries.defaultMaxAttempts Info
    }


{-| Retry after waiting 1 sec, and default to retrying up to 60 times.
-}
retries : { defaultMaxAttempts : Int, msDelayBetweenRetries : Posix }
retries =
    { defaultMaxAttempts = 60
    , msDelayBetweenRetries = Time.millisToPosix 1000
    }


endpointUrl : String
endpointUrl =
    "https://notify.bugsnag.com"
