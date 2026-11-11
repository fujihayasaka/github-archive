# Chatterbox

## Overview

This is a simple golang client to send messages to
[chatterbox](https://github.com/github/chatterbox), GitHub's simple API to send
messages into chat.

## Example

```go
package main

import (
 "context"
 "github.com/github/go-chatterbox/v4"
 "log"
 "os"
)

func main() {
 ctx := context.Background()
 token := os.Getenv("CHATTERBOX_TOKEN")
 url, ok := os.LookupEnv("CHATTERBOX_URL")
 if !ok {
  url = "https://chatterbox.githubapp.com"
 }

 // use the one-line version for single messages
 err := chatterbox.Say(ctx, token, url, chatterbox.SayPayload{Topic: "dumping-ground", Text: "Hello, world!"})
 if err != nil {
  log.Fatalf("Error sending to chatterbox: %v", err)
 }

 // use the chatterbox.Client version when you might be sending multiple
 // messages around
 client, err := chatterbox.New(token, url)
 if err != nil {
  log.Fatalf("Error connecting to chatterbox: %v", err)
 }
 err = client.Say(ctx, chatterbox.SayPayload{Topic: "dumping-ground", Text: "Hello, world again!"})
 if err != nil {
  log.Fatalf("Error sending to chatterbox: %v", err)
 }

 // set the colored stripe in slack to red, and add a footer
 // using the client we just created
 message := chatterbox.NewMessage("This message has a stripe")
 message.Color(chatterbox.RED)
 message.Footer("powered by github/go-chatterbox")
 err = client.SayMessage(ctx, SayPayload{Topic: "dumping-ground", Message: message})
 if err != nil {
  log.Fatalf("Error sending to chatterbox: %v", err)
 }
}
```

Check out `godoc -ex chatterbox` for more documentation

## Contributing

This repository is owned by [runtime-platform](https://github.com/github/runtime-platform/), and we welcome contributions! To learn more about developing and making updates to this repo, please see [the contributing guide](./CONTRIBUTING.md).
