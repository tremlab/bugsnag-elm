module Bugsnag exposing
    ( Bugsnag, Level(..), Token, token, Environment, environment, Scope, scope, CodeVersion, codeVersion
    , scoped, send
    , User
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

    Bugsnag.token "12345abcde........"

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


{-| A record of datapoints bugsnag's api can accept for user data.
To display additional custom user data alongside these standard fields on the Bugsnag website,
the custom data should be included in the metaData object in a user object.
-}
type alias User =
    { id : Int
    , username : String
    , email : String
    }


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

    Bugsnag.token "12345abcde....."

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
  - `Level` - severity, e.g. `Error`, `Warning`, `Debug`
  - 'Maybe User' - if available, report user data (id, name, email)
  - `String` - message, e.g. "Auth server was down when user tried to sign in."
  - `Dict String Value` - arbitrary metadata, e.g. `{"username": "rtfeldman"}`

If the message was successfully sent to Bugsnag, the [`Task`](http://package.elm-lang.org/packages/elm-lang/core/latest/Task#Task)
succeeds with the [`Uuid`](http://package.elm-lang.org/packages/danyx23/elm-uuid/latest/Uuid#Uuid)
it generated and sent to Bugsnag to identify the message. Otherwise it fails
with the [`Http.Error`](http://package.elm-lang.org/packages/elm-lang/http/latest/Http#Error)
responsible.

-}
send :
    Token
    -> CodeVersion
    -> Scope
    -> Environment
    -> Level
    -> Maybe User
    -> String
    -> Dict String Value
    -> Task Http.Error Uuid
send vtoken vcodeVersion vscope venvironment level maybeUser message metadata =
    Time.now
        |> Task.andThen (sendWithTime vtoken vcodeVersion vscope venvironment level message metadata maybeUser)



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


sendWithTime :
    Token
    -> CodeVersion
    -> Scope
    -> Environment
    -> Level
    -> String
    -> Dict String Value
    -> Maybe User
    -> Posix
    -> Task Http.Error Uuid
sendWithTime vtoken vcodeVersion vscope venvironment level message metadata maybeUser time =
    let
        uuid : Uuid
        uuid =
            uuidFrom vtoken vscope venvironment level message metadata time

        body : Http.Body
        body =
            toJsonBody vscope vcodeVersion venvironment level message uuid maybeUser metadata
    in
    { method = "POST"
    , headers =
        [ tokenHeader vtoken
        , Http.header "Bugsnag-Payload-Version" "5"
        ]
    , url = endpointUrl
    , body = body
    , resolver = Http.stringResolver (\_ -> Ok ()) -- TODO
    , timeout = Nothing
    }
        |> Http.task
        |> Task.map (\() -> uuid)


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


toJsonBody : Scope -> CodeVersion -> Environment -> Level -> String -> Uuid -> Maybe User -> Dict String Value -> Http.Body
toJsonBody (Scope vscope) (CodeVersion vcodeVersion) (Environment venvironment) level message uuid maybeUser metadata =
    let
        userInfo =
            case maybeUser of
                Just user ->
                    [ ( "user"
                      , Encode.object
                            [ ( "id", Encode.int user.id )
                            , ( "name", Encode.string user.username )
                            , ( "email", Encode.string user.email )
                            ]
                      )
                    ]

                Nothing ->
                    []
    in
    -- See https://Bugsnag.com/docs/api/items_post/ for schema
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
                [ ( "exceptions"
                  , Encode.list identity
                        [ Encode.object
                            [ ( "errorClass", Encode.string message )

                            -- , ( "message", Encode.string message ) any valuable data to report here? userImpact?
                            , ( "stacktrace", Encode.list identity [] )
                            ]
                        ]
                  )
                , ( "context", Encode.string vscope )
                , ( "severity", Encode.string (levelToString level) )
                , ( "metaData"
                  , metadata
                        |> Dict.insert "uuid" (Encode.string (Uuid.toString uuid))
                        |> Encode.dict identity identity
                  )
                , ( "app"
                  , Encode.object
                        [ ( "version", Encode.string vcodeVersion )
                        , ( "releaseStage", Encode.string venvironment )
                        ]
                  )
                ]
            ]
      )
    ]
        ++ userInfo
        |> Encode.object
        |> Http.jsonBody


tokenHeader : Token -> Http.Header
tokenHeader (Token vtoken) =
    Http.header "Bugsnag-Api-Key" vtoken


{-| Return a [`Bugsnag`](#Bugsnag) record configured with the given
[`Environment`](#Environment) and [`Scope`](#Scope) string.

    Bugsnag = Bugsnag.scoped "Page/Home.elm"

    Bugsnag.debug "Hitting the hats API." Dict.empty

    [ ( "Payload", toString payload ) ]
        |> Dict.fromList
        |> Bugsnag.error "Unexpected payload from the hats API."

-}
scoped : Token -> CodeVersion -> Environment -> Maybe User -> String -> Bugsnag
scoped vtoken vcodeVersion venvironment maybeUser scopeStr =
    let
        vscope =
            Scope scopeStr
    in
    { error = send vtoken vcodeVersion vscope venvironment Error maybeUser
    , warning = send vtoken vcodeVersion vscope venvironment Warning maybeUser
    , info = send vtoken vcodeVersion vscope venvironment Info maybeUser
    }


endpointUrl : String
endpointUrl =
    "https://notify.bugsnag.com"
