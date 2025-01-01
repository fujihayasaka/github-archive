package main

import (
	"log"

	"github.com/github/authnd/cmd/authnd-client/cmd"
)

func main() {
	err := cmd.RootCmd.Execute()
	if err != nil {
		log.Fatal(err)
	}
}
