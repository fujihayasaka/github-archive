// Command rulehelp populates the database with the latest rule help for a tool.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/log"
)

func main() {
	flag.Bool("commit", false, "Commit changes")
	filePath := flag.String("path", "", "Target SARIF file with rules description (Required)")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of %s: [-commit] -path <rules.sarif>\n", os.Args[0])
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NFlag() == 0 {
		flag.Usage()
		os.Exit(1)
	}

	if *filePath == "" {
		fmt.Fprintln(os.Stderr, "Must specify a SARIF file to read with --path")
		os.Exit(1)
	}

	if err := realMain(); err != nil {
		log.WithError(err).Error("Unexpected error")
		os.Exit(1)
	}
}

func realMain() error {
	_, err := fmt.Fprintln(os.Stderr, "rulehelp is deprecated: please remove it from this workflow")
	return err
}
