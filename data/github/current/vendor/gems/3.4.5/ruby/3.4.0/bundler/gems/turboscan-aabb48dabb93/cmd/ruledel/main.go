//nolint:golint,errcheck,forcetypeassert
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"

	"github.com/pkg/errors"
)

func main() {
	err := realMain("codeql")
	if err != nil {
		log.Fatalf("%+v", err)
	}
}

// dig descends into a json document key by key, returning the result
func dig(doc any, keys ...string) any {
	res := doc
	for _, key := range keys {
		doc := res.(map[string]any)
		res = doc[key]
	}
	return res
}

// appendRule adds a rule to the first run of a sarif document
func appendRule(sarif map[string]any, rule map[string]any) error {
	for _, run := range sarif["runs"].([]any) {
		driver := dig(run, "tool", "driver").(map[string]any)
		rules := driver["rules"].([]any)
		driver["rules"] = append(rules, rule)
		return nil
	}
	return errors.New("no runs to append rule to")
}

// index returns a map of sarif identifiers to rules
func index(sarif map[string]any) map[string]map[string]any {
	out := make(map[string]map[string]any)
	for _, run := range sarif["runs"].([]any) {
		for _, rule := range dig(run, "tool", "driver", "rules").([]any) {
			rule := rule.(map[string]any)
			name := rule["name"].(string)
			out[name] = rule
		}
	}
	return out
}

func unmarshal(data []byte, err error) (map[string]any, error) {
	if err != nil {
		return nil, err
	}
	doc := make(map[string]any)
	err = errors.Wrap(json.Unmarshal(data, &doc), "failed to unmarshal sarif")
	return doc, err
}

func realMain(name string) error {
	path := fmt.Sprintf("ts/sarif/ruledata/%s.sarif", name)
	deletedPath := fmt.Sprintf("ts/sarif/ruledata/%s-deleted.sarif", name)

	git, err := exec.LookPath("git")
	if err != nil {
		return errors.Wrap(err, "failed to find git")
	}

	// make sure that the main branch exists locally so we can determine the previous rules
	revParse := exec.Command(git, "rev-parse", "--verify", "main")
	_ = revParse.Run()
	if revParse.ProcessState.ExitCode() == 128 {
		trackMain := exec.Command(git, "branch", "--track", "main", "origin/main")
		trackMain.Stderr = os.Stderr

		if err := trackMain.Run(); err != nil {
			return errors.Wrap(err, "failed to track main branch")
		}
	}

	cmd := exec.Command(git, "show", "main:"+path)

	previous, err := unmarshal(cmd.Output())
	if err != nil {
		return err
	}
	current, err := unmarshal(os.ReadFile(path))
	if err != nil {
		return err
	}
	deleted, err := unmarshal(os.ReadFile(deletedPath))
	if err != nil {
		return err
	}

	previousRules := index(previous)
	currentRules := index(current)
	deletedRules := index(deleted)

	var modified bool

	for id, previousRule := range previousRules {
		if _, currentExists := currentRules[id]; !currentExists {
			if _, deletedExists := deletedRules[id]; !deletedExists {
				fmt.Printf("saving %s to deleted rules\n", id)
				if err := appendRule(deleted, previousRule); err != nil {
					return err
				}
				modified = true
			}
		}
	}

	if modified {
		data, err := json.MarshalIndent(deleted, "", "  ")
		if err != nil {
			return errors.Wrap(err, "failed to marshal deleted rules")
		}
		return errors.Wrap(os.WriteFile(deletedPath, data, 0o644), "failed to write deleted rules")
	}

	return nil
}
