// Command ghapi provides a small utility to test various API calls.
package main

import (
	"fmt"
	"os"

	"github.com/github/turboscan/cmd/ghapi/root"
)

func main() {
	if err := root.GHApiCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%+v\n", err)
		os.Exit(1)
	}
}
