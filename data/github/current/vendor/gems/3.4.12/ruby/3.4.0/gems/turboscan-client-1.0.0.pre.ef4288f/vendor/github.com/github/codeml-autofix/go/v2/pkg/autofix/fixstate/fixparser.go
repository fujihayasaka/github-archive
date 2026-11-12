// Package fixstate provides functions to process the model response
package fixstate

import (
	"regexp"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// Process the dependencies section of the model response to extract the list of
// dependencies we want to add, if any.
func processDependenciesToAddSection(dependenciesPlan string) ([]string, autofix.AutofixError) {
	// The LLM sometimes injects * around Yes/No, so we need to remove them.
	dependenciesPlan = strings.ReplaceAll(dependenciesPlan, "*", "")

	// look for `1. yes/no` or `yes/no`
	if dependenciesPlan == "" {
		// empty plan means no dependencies
		return []string{}, nil
	}

	hasNewDepsReg := regexp.MustCompile(`(?i)(?:\d\.|^)\s*[^\n]*\b(\w+)(?:\n|$)`) // extract the last word from the first line.
	hasNewDepsMatch := hasNewDepsReg.FindStringSubmatch(strings.ToLower(dependenciesPlan))
	if len(hasNewDepsMatch) == 0 {
		// failed to extract dependencies. Not an error, just means no new dependencies.
		return []string{}, nil
	}

	newDependencies := strings.EqualFold(hasNewDepsMatch[1], "yes") || strings.EqualFold(hasNewDepsMatch[1], "maybe")

	if !newDependencies {
		return []string{}, nil
	}

	// look for `2. ... - `packagename` (all occurrences)
	// first find everything after the end of hasNewDepsMatch
	locationOfFirstMatch := hasNewDepsReg.FindStringIndex(dependenciesPlan)
	commandArea := dependenciesPlan[locationOfFirstMatch[1]:]

	// strip any leading "2. " of the command area
	commandArea = regexp.MustCompile(`(?i)^\s*2\.\s*`).ReplaceAllString(commandArea, "")

	bulletRegex := regexp.MustCompile("(?im)(?:^\\s*-? ?`)([^`]+)`") // im for case insensitive and multiline. Multiline needed for "^" to match the start of any line.
	installCommandsGroups := bulletRegex.FindAllStringSubmatch(commandArea, -1)
	installCommands := utils.Map(installCommandsGroups, func(match []string) string {
		return strings.TrimSpace(match[1])
	})
	installCommands = utils.Map(installCommands, strings.TrimSpace)

	// remove npm/yarn add/install commands:
	installCommands = utils.Map(installCommands, func(command string) string {
		regex := regexp.MustCompile(`(npm|yarn) (add|install) `)
		return regex.ReplaceAllString(command, "")
	})

	if len(installCommands) == 0 {
		return nil, &autofix.BadModelOutputError{Err: errors.Errorf("failed to list package names. Full plan: \n %s", dependenciesPlan)}
	}

	return installCommands, nil
}
