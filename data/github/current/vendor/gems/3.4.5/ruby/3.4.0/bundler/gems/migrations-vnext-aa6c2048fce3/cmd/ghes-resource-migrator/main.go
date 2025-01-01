// Package main is the main package for the ghes-resource-migrator
// utility.
package main

import (
	"fmt"
	"os"

	"github.com/github/migrations-vnext/cmd/ghes-resource-migrator/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
