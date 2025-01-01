# Chatops RPC

Chatops RPC server and command line client implementation.

```go
package main

import (
 "context"
 "log"
 "net/http"
 "os"

 "github.com/github/go-chatops/v2"
)

func main() {
 ns := chatops.NewNamespace("deploy")
 ns.Help = "deploy some things"
 m, err := ns.Add("options")
 if err != nil {
  log.Fatal(err)
 }
 m.Help = "hubot deploy options <app> - List available environments for <app>"
 m.Regex = "options(?: (?<app>\\S+))?"
 m.Params = []string{"app"}
 m.On(func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
  return &chatops.CommandResponse{
   Result: "Found: " + req.Method,
  }, nil
 })

 handler, err := chatops.NewHandler(ns, "https://my-chatops-server.com")
 if err != nil {
  log.Fatal(err)
 }

 key, err := chatops.ReadPEMPublicKey([]byte(os.Getenv("CHATOPS_AUTH_PUBLIC_KEY")))
 if err != nil {
  log.Fatal(err)
 }
 handler.AddBot(key)

 mux := http.NewServeMux()
 handler.Setup(mux)
 log.Fatal(http.ListenAndServe(":8181", mux))
}
```

## Ready to use chatops commands

The `go-chatops` includes some chatops commands that you can import and start using:

* [`pprof`](/chatops/pprof): The `pprof` chatops command provides a way to download pprof profile dumps and inspect them on your localhost.

As an example this is how you add the `pprof` chatop:

```go
package main

import (
 "github.com/github/go-chatops/v2"
 "github.com/github/go-chatops/v2/chatops/pprof"
)


func main() {
 ns := chatops.NewNamespace("foo")
 ns.Register(pprof.ProfileChatop())

 // setup and run server ...
}
```

Please checkout the `pprof` command's own godoc documentation inside the package for more information.

## Authentication

Chatops via RPC requires authentication via [public key signing](https://github.com/github/hubot2/blob/main/docs/rpc_chatops_protocol.md#authentication). These keys need to be added to the `chatops.Handler` with `AddBot(key)`.

If you're using [go-config](https://github.com/github/go-config), you can import keys from the environment:

```go
type Config struct {
 ChatopsAuthPublicKey  *rsa.PublicKey `config:",env=CHATOPS_AUTH_PUBLIC_KEY"`
}
```

Or to load the keys yourself, use `ReadPEMPublicKey`:

```go
key, err := chatops.ReadPEMPublicKey([]byte(os.Getenv("CHATOPS_AUTH_PUBLIC_KEY")))
```

For production, you'll need to [set/use these keys](https://thehub.github.com/engineering/products-and-services/internal/chatops/#production) with your deployed code.

In development, hubot uses a hardcoded key pair (in [hubot2](https://github.com/github/hubot2), `test/hubot-test.pub` and `test/hubot-test.pem`). For your convenience and for use during tests, these keys are included with this library in the `HubotTestPublicKey` and `HubotTestPrivateKey` variables.

To set up a chatops service for local development with hubot-classic including auth:

```go
 key, err := chatops.ReadPEMPublicKey(chatops.HubotTestPublicKey)
 if err != nil {
  log.Fatal(err)
 }

 ns := chatops.NewNamespace("demo")
 handler, _ := chatops.NewHandler(ns, "https://localhost:8080/")
 handler.AddBot(key) // this configures auth

 // ...
```

## Security

This implementation now includes optional security features for creating chatops commands which are restrictied by a user's role, the chatroom, or needing two factor auth.

```go
func main() {
 config, err := security.LoadSecurityConfig("security-config.yaml")
 if err != nil {
  log.Fatal(err)
 }

 ldapClient, err := security.InitializeLDAPClient("ldap-conf.yaml", os.GetEnv("LDAP_READONLY_PASSWORD"))
 if err != nil {
  log.Fatal(err)
 }
 validator := security.Validator{
  Config: *config,
  LDAP: *ldapClient,
  Auth: security.DuoTwoFactor{ Duo: ... },
 }
 prompter := slack.Client{
  BaseURL: "https://www.slack.com/api",
  Token:   os.GetEnv("SLACK_API_TOKEN"),
 }

 ns := chatops.NewNamespace("deploy")
 ns.Help = "deploy some things"
 m := ns.Add("options")
 m.Help = "hubot deploy options <app> - List available environments for <app>"
 m.Regex = "options(?: (?<app>\\S+))?"
 m.Params = []string{"app"}
 m.On(security.WrapWithAuthorization(&validator, prompter,
  func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
  return &chatops.CommandResponse{
   Result: "Found: " + req.Method,
  }, nil
 })

 handler, err := chatops.NewHandler(ns, "https://my-chatops-server.com")
 if err != nil {
  log.Fatal(err)
 }

 mux := http.NewServeMux()
 handler.Setup(mux)
 log.Fatal(http.ListenAndServe(":8181", mux))
}
```

The above code has some external dependencies which are up to the user to create.  LDAP is used for role-based auth, DuoMobile for two factor requests, and Slack for the chat messages.  However the Validator object only asks for  interfaces to be satisfied so it's straighforward to use different services, or inject noop dependencies if the behavior is not needed.

For more instructions, including the security config file format see: [security/validator.go](/security/validator.go)

## Client

There is also a client here in addition the the chatops server which lets you make signed requests to remote servers.

```go
package main

import (
 "fmt"
 "log"
 "net/http"
 "os"
 "time"

 chatops "github.com/github/go-chatops/v2"
)

func main() {
 key, err := chatops.ReadPEMPrivateKey([]byte(os.Getenv("CHATOPS_AUTH_PRIVATE_KEY")))
 if err != nil {
  log.Fatal(err)
 }
 client := chatops.NewClientWithKey("https://provisioning.github.net/_instance_chatops", key).
  WithOptions(chatops.ClientOptions{
   RequestTimeout: time.Duration(30 * time.Second),
   AuthToken:      os.Getenv("CHATOPS_AUTH_TOKEN"),
  })

 resp, status, err := client.Command("list", os.Getenv("USER"), "testing-channel", "list db-mysql"
  map[string]string{
   "arguments": "db-mysql",
  })

 if err != nil {
  log.Fatal(err)
 }

 if status.StatusCode == http.StatusOK {
  fmt.Println("Success!")
  fmt.Printf("%+v\n", resp)
 }
}
```

## Contributing

This repository is owned by [@dev-frameworks](https://github.com/github/dev-frameworks/), and we welcome contributions! To learn more about developing and making updates to this repo, please see [the contributing guide](./CONTRIBUTING.md).
