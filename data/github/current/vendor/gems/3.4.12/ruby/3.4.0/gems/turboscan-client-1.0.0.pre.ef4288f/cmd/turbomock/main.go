// Command turbomock pretends to be a Turboscan service.
package main

import (
	"log"

	"github.com/github/turboscan/cmd/turbomock/root"
)

func main() {
	if err := root.Execute(); err != nil {
		log.Fatal(err)
	}
}
