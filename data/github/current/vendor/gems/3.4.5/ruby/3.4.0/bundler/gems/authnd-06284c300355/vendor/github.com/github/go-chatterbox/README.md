# Chatterbox [![GoDoc](https://pkg.go.dev/badge/github.com/github/docs)](https://gopkgs.githubapp.com/github.com/github/go-chatterbox)

## Overview

This is a simple golang client to send messages to
[chatterbox](https://github.com/github/chatterbox), GitHub's simple API to send
messages into chat.

## Example

```go
package main

import (
	"github.com/github/go-chatterbox"
	"log"
	"os"
)

func main() {
	token := os.Getenv("CHATTERBOX_TOKEN")
	url, ok := os.LookupEnv("CHATTERBOX_URL")
	if !ok {
		url = "https://chatterbox.githubapp.com"
	}

	// use the one-line version for single messages
	err := chatterbox.Say(token, url, "dumping-ground", "Hello, world!")
	if err != nil {
		log.Fatalf("Error sending to chatterbox: %v", err)
	}

	// use the chatterbox.Client version when you might be sending multiple
	// messages around
	client, err := chatterbox.New(token, url)
	if err != nil {
		log.Fatalf("Error connecting to chatterbox: %v", err)
	}
	err = client.Say("dumping-ground", "Hello, world again!")
	if err != nil {
		log.Fatalf("Error sending to chatterbox: %v", err)
	}

	// set the colored stripe in slack to red, and add a footer
	// using the client we just created
	message := chatterbox.NewMessage("This message has a stripe")
	message.Color(chatterbox.RED)
	message.Footer("powered by github/go-chatterbox")
	err = client.SayMessage("dumping-ground", message)
	if err != nil {
		log.Fatalf("Error sending to chatterbox: %v", err)
	}
}

```

Check out `godoc -ex chatterbox` for more documentation

## Contributing

 To learn more about developing and making updates to this repo, please checkout [the contributing guide](https://github.com/github/frameworks-containers/tree/main/docs/go-libs-common-docs/CONTRIBUTING.md).
