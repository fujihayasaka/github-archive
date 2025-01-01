// Command rulehelp populates the database with the latest rule help for a tool.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts/sarif"
	v210turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/google/go-cmp/cmp"
)

func main() {
	before := flag.String("before", "", "Path to the old rule help SARIF file.")
	after := flag.String("after", "", "Path to the new rule help SARIF file.")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of %s: --before <old-rules.sarif> --after <new-rules.sarif>\n", os.Args[0])
		flag.PrintDefaults()
	}
	flag.Parse()

	if *before == "" || *after == "" {
		flag.Usage()
		os.Exit(1)
	}

	if err := realMain(before, after); err != nil {
		log.WithError(err).Error("Unexpected error: ")
		os.Exit(1)
	}
}

func realMain(beforePath, afterPath *string) error {
	before, err := sarif.FromFile(*beforePath)
	if err != nil {
		return err
	}
	after, err := sarif.FromFile(*afterPath)
	if err != nil {
		return err
	}

	if len(before.Runs) != 1 || len(after.Runs) != 1 {
		return errors.New("Expected exactly one SARIF run per-file.")
	}

	fmt.Printf("%s -> %s\n", before.Runs[0].Tool.Driver.SemanticVersion, after.Runs[0].Tool.Driver.SemanticVersion)

	beforeRules := map[string]*v210turboscan.Rule{}
	for _, rule := range before.Runs[0].Tool.Driver.Rules {
		beforeRules[rule.Id] = rule
		rule.Properties.QueryURI = "" // The query URI contains the commit that CodeQL was built from, so we want to ignore it.
	}
	afterRules := map[string]*v210turboscan.Rule{}
	for _, rule := range after.Runs[0].Tool.Driver.Rules {
		afterRules[rule.Id] = rule
		rule.Properties.QueryURI = ""
	}

	diffs := cmp.Diff(beforeRules, afterRules)

	fmt.Println(diffs)

	return nil
}
