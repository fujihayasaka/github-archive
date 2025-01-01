// Checks if hydro schemas have gone out of sync
package main

import (
	"fmt"
	"os"

	"github.com/github/turboscan/cmd/lint-proto/root"
)

func main() {
	if err := root.LintProtoCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%+v\n", err)
		os.Exit(1)
	}
}
