// This package provides function to gather environment varibales that are used in database.yml file in Dotcom
// and compare it with federation of variables in secrets-federation repo for environments that mentioned in that package.
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"slices"

	"gopkg.in/yaml.v3"
)

// relative paths for database.yml in Dotcom and federation directory in secrets-federation
const configurationFilepath = "github/config/protected/database.yml"
const federationDir = "secrets-federation/config/federation"

// predefined patterns for fetching environment variable data, environments to use and directories for GitHub Actions
var (
	// Regex to match GitHub.environment.fetch with a default value
	// Pattern for GitHub.environment["VAR_NAME"] with optional default value
	defaultValuePattern1 = regexp.MustCompile(`GitHub\.environment\.fetch\([^)]+,\s*[^)]+\)`)
	defaultValuePattern2 = regexp.MustCompile(`GitHub\.environment\["[^"]+"\]\s*\|\|`)
	defaultValuePattern3 = regexp.MustCompile(`GitHub\.secrets\.fetch\([^)]+,\s*[^)]+\)`)

	// Pattern 1: Match GitHub.environment["VAR_NAME"]
	pattern1 = `GitHub\.environment\["([^"]+)"\]`
	pattern2 = `GitHub\.environment\['([^']+)'\]`
	r1       = regexp.MustCompile(pattern1)
	r2       = regexp.MustCompile(pattern2)

	// Pattern 2: Match GitHub.environment.fetch("VAR_NAME")
	pattern3 = `GitHub\.environment\.fetch\("([^"]+)"`
	pattern4 = `GitHub\.environment\.fetch\('([^']+)'`
	r3       = regexp.MustCompile(pattern3)
	r4       = regexp.MustCompile(pattern4)

	// Pattern 3: Match GitHub.secret.fetch("VAR_NAME")
	pattern5 = `GitHub\.secrets\.fetch\("([^"]+)"`
	pattern6 = `GitHub\.secrets\.fetch\('([^']+)'`
	r5       = regexp.MustCompile(pattern5)
	r6       = regexp.MustCompile(pattern6)

	federationEnvironments = []string{
		"gh-console",
		"proxima-staffship-gh-console",
		"proxima-prod-weu-01-gh-console",
		"proxima-prod-sdc-01-gh-console",
		"proxima-prod-ae-01-gh-console",
		"proxima-prod-cus-01-gh-console",
	}

	githubWorkspace = os.Getenv("GITHUB_WORKSPACE")

	configurationFilePath = filepath.Join(githubWorkspace, configurationFilepath)
	federaionDirectory    = filepath.Join(githubWorkspace, federationDir)
)

// main structure to parse in secrets-federation
type federation struct {
	To []to `yaml:"to"`
}

// structure for federation in secrets-federation
type to struct {
	App          string      `yaml:"app"`
	Backend      string      `yaml:"backend"`
	Environment  interface{} `yaml:"environment,omitempty"`
	Environments []string    `yaml:"environments,omitempty"`
	Key          string      `yaml:"key,omitempty"`
}

// main fetch environment variables from database.yml and then gather secrets that should be federated for each
// specified environment and compare that list with data from database.yml
func main() {
	databaseConfugurationVariables := readDotcomConfiguration(configurationFilePath)
	fmt.Printf("Database configuration count: %d\n", len(databaseConfugurationVariables))

	allMissedVariables := make(map[string]map[string]bool)

	for _, environment := range federationEnvironments {
		fmt.Printf("Checking environment: %s\n", environment)

		missedVariables := checkExistenceOfConfiguration(environment, databaseConfugurationVariables)
		if len(missedVariables) > 0 {
			allMissedVariables[environment] = missedVariables
		}
	}

	if len(allMissedVariables) > 0 {
		for environment, missedVariables := range allMissedVariables {
			fmt.Printf("\nMissed variables in environment %s:\n", environment)

			fmt.Println("Please create PR to secrets-federation and add federation for the following variables:")
			for variable := range missedVariables {
				fmt.Printf("- %s\n", variable)
			}
		}

		printHelp()
		os.Exit(1)
	}
}

// checkExistenceOfConfiguration checks how many secrets are missing from incoming dataset in secrets-federation for specified environment.
func checkExistenceOfConfiguration(environment string, datatabaseConfigurations map[string]bool) map[string]bool {
	secretFederationVariables := readSecretsFederation(federaionDirectory, environment)

	missedVariables := make(map[string]bool)

	for variable := range datatabaseConfigurations {
		if _, found := secretFederationVariables[variable]; !found {
			missedVariables[variable] = true
		}
	}

	fmt.Printf("Secret federation count for %s: %d\n", environment, len(secretFederationVariables))

	return missedVariables
}

// readDotcomConfiguration reads database.yml configuration file and extracts environment variables that are used for read-only mode
func readDotcomConfiguration(filePath string) map[string]bool {
	fmt.Println("Script to check for secrets in dotcom configuration")

	file, err := os.Open(filePath)
	if err != nil {
		fmt.Printf("Error reading file %s: %v\n", filePath, err)
		return nil
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)

	insideCondition := false
	insideElseBlock := false

	collection := make(map[string]bool)

	for scanner.Scan() {
		line := scanner.Text()

		if insideCondition && strings.Contains(line, `<% else %>`) {
			insideCondition = false
			insideElseBlock = true
			continue
		}

		if insideElseBlock {
			if strings.Contains(line, `<% end %>`) {
				insideElseBlock = false
			}
			continue
		}

		if strings.Contains(line, `if GitHub.environment["GITHUB_PRODUCTION_RO_CONSOLE"]`) {
			insideCondition = true
			continue
		}

		if !strings.Contains(line, "GitHub.environment") {
			continue
		}

		// Use it to check if a line should be skipped
		if defaultValuePattern1.MatchString(line) {
			// Skip this line as it has a default value
			continue
		}

		if defaultValuePattern2.MatchString(line) {
			// Skip this line as it has a default value
			continue
		}

		env_var := readVariable(line)
		collection[env_var] = true
	}

	return collection
}

// readVariable reads a line and extract variable name from it
func readVariable(line string) string {
	// Try to match pattern 1
	matches := r1.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try to match pattern 1 with single quotes
	matches = r2.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try to match pattern 2
	matches = r3.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try to match pattern 2 with single quotes
	matches = r4.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try to match pattern 3
	matches = r5.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try to match pattern 3 with single quotes
	matches = r6.FindStringSubmatch(line)
	if len(matches) > 1 {
		return matches[1]
	}

	return "UNKNOWN_VARIABLE"
}

// readSecretsFederation reads secrets-federation repository and extracts set of environment variables for specified environment
func readSecretsFederation(secretsFederationDirectoryPath, environment string) map[string]bool {
	collection := make(map[string]bool)

	// Walk through all directories
	err := filepath.Walk(secretsFederationDirectoryPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories
		if info.IsDir() {
			return nil
		}

		// Check if file is a YAML file
		if strings.HasSuffix(path, ".yml") || strings.HasSuffix(path, ".yaml") {
			secretFederationVariables, err := processYAMLFile(path, environment)
			if err != nil {
				fmt.Printf("Error processing file %s: %v\n", path, err)
				return nil // Continue to next file
			}

			// Add found variables to our map
			for _, name := range secretFederationVariables {
				collection[name] = true
			}
		}

		return nil
	})

	if err != nil {
		fmt.Printf("Error walking directories: %v\n", err)
		os.Exit(1)
	}

	return collection
}

// processYAMLFile processes YAML file and extract environment variables that match our criteria
func processYAMLFile(filePath, environment string) ([]string, error) {
	// Read the YAML file
	yamlData, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("error reading file: %v", err)
	}

	// Define the YAML structure
	var federation map[string]federation

	// Parse the YAML
	if err := yaml.Unmarshal(yamlData, &federation); err != nil {
		return nil, fmt.Errorf("error parsing YAML: %v", err)
	}

	// Find environment variables that match our criteria
	var matchingVars []string = []string{}

	for envVar, dest := range federation {
		for _, to := range dest.To {
			if to.App == "shells" && to.Backend == "vault" {
				if len(to.Environments) > 0 && slices.Contains(to.Environments, environment) {
					matchingVars = append(matchingVars, getFederationVariableName(envVar, to))
					break // Found a match, no need to check other destinations
				}

				// Check the environment field which could be a string or array
				if to.Environment != nil {
					switch env := to.Environment.(type) {
					case string:
						// Simple string case
						if env == environment {
							matchingVars = append(matchingVars, getFederationVariableName(envVar, to))
							break
						}
					case []string:
						// Array case
						for _, str := range env {
							if str == environment {
								matchingVars = append(matchingVars, getFederationVariableName(envVar, to))
								break
							}
						}
					case []interface{}:
						// Array of interface{} case
						for _, item := range env {
							if str, ok := item.(string); ok && str == environment {
								matchingVars = append(matchingVars, getFederationVariableName(envVar, to))
								break
							}
						}
					}
				}
			}
		}
	}

	// Sort them alphabetically for better readability
	sort.Strings(matchingVars)

	return matchingVars, nil
}

// getFederationVariableName gets proper name of environment variables from secrets-federation configuration parsed record
func getFederationVariableName(name string, federation to) string {
	if federation.Key != "" {
		return federation.Key
	}
	return name
}

// printHelp prints some help to understand how to federate new secret
func printHelp() {
	fmt.Println()
	fmt.Println("Example of how to copy variable from its source to ephemeral shells environment:")
	fmt.Println(`VARIABLE_NAME:
  to:
  - app: shells
    backend: vault
    environment: gh-console`)
	fmt.Println()
}
