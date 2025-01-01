// Package main implements the gh-kustomize command line tool.
package main

import (
	"os"

	"github.com/github/gh-kustomize/v3/cmd"
)

func main() {
	exitCode, _ := cmd.Execute()
	os.Exit(exitCode)
}
