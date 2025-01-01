// Package main executes the importcli.
package main

import (
	"fmt"
	"os"

	"github.com/github/migrations-vnext/cmd/importcli/cmd"
)

func main() {
	// Execute the root command which will include all subcommands
	if err := cmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
