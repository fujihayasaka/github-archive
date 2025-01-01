# `identity` Package

The `identity` package provides a set of abstractions and types to represent and manage different types of GitHub actors. The intended goal for this package is to be the universal "actor" (aka `current_user`) that Go services outside of the monolith can use.

## Instantiation

First, get the package:

```bash
go get "github.com/github/authnd/client/exp/identity"
```

To create an instance of an `Actor`, you can use any of the exposed constructor methods (i.e. `NewUserActorNoContext`, `NewUserActorViaUserToServerToken`, `NewBotActor`, `NewIntegrationActor`, etc.). However, most of these constructors will require certain IDs and arguments.

More conveniently, if you have Authnd attributes or an exhange token (through the `Authenticate` or `ExchangeToken` RPCs), you can instantiate an Actor with the response.

If you want to instantiate the Actor from an authnd response, you'll also need the "parsing" package.

```bash
go get "github.com/github/authnd/client/exp/identity/parsing"
```

```golang
import (
  "fmt"
  "github.com/github/authnd/client"
  "github.com/github/authnd/client/proto"
  "github.com/github/authnd/client/exp/identity"
  "github.com/github/authnd/client/exp/identity/parsing"
)

func getActor() (identity.Actor, error) {
  authenticator, err := client.NewAuthenticator(
    TWIRP_ADDR,
    "service_catalog_name",
  )
  creds := client.NewAccessTokenCredentials(token)
  req := client.NewAuthenticateRequest(creds)
  resp := authenticator.Authenticate(context.Background(), req)
  
  if !resp.Succeeded() {
    return
  }
  
  actor, err := parsing.ActorFromAuthenticateAttributes(resp.Attributes)
  if err != nil {
      return
  }
}

func main() {
  actor, _ := getActor()
  fmt.Println("Hello " + actor.ID())
  fmt.Println("Type: " + actor.Type())
}

```
