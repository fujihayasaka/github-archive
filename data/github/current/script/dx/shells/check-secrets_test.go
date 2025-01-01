// This tests are mostly for checking how functions work and for increasing understanding how they work. It not supposed to be run in GitHub Actions for now.
package main

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
)

// relative path in Codespaces
const codespacesDatabaseYaml = "../../../config/protected/database.yml"

func TestProcessYAMLFile(t *testing.T) {
	// Setup temporary test directory
	tempDir := t.TempDir()

	// Create test YAML file
	testYAML := `
MYSQL_MYSQL1_DATABASE:
  to:
  - app: shells
    backend: vault
    environment: gh-console
  - app: github
    backend: vault
    environment: production

MYSQL_MYSQL1_HOST:
  to:
  - app: shells
    backend: vault
    environments:
      - gh-console
      - production
  - app: github
    backend: other
    environment: production

MYSQL_MYSQL1_PASSWORD:
  to:
  - app: shells
    backend: vault
    environment:
      - gh-console
  - app: other
    backend: vault

MYSQL_WITH_DEFAULT:
  to:
  - app: unrelated
    backend: unrelated
`

	yamlPath := filepath.Join(tempDir, "federation.yaml")
	if err := os.WriteFile(yamlPath, []byte(testYAML), 0644); err != nil {
		t.Fatalf("Failed to write test YAML file: %v", err)
	}

	// Test cases
	tests := []struct {
		name             string
		targetEnv        string
		targetApp        string
		targetBackend    string
		expectedVars     []string
		shouldFindErrors bool
	}{
		{
			name:          "Find shells vault gh-console variables",
			targetEnv:     "gh-console",
			targetApp:     "shells",
			targetBackend: "vault",
			expectedVars:  []string{"MYSQL_MYSQL1_DATABASE", "MYSQL_MYSQL1_HOST", "MYSQL_MYSQL1_PASSWORD"},
		},
		{
			name:          "Find shells vault production variables",
			targetEnv:     "production",
			targetApp:     "shells",
			targetBackend: "vault",
			expectedVars:  []string{"MYSQL_MYSQL1_HOST"},
		},
		{
			name:          "Find non-existent target",
			targetEnv:     "staging",
			targetApp:     "shells",
			targetBackend: "vault",
			expectedVars:  []string{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			vars, errs := processYAMLFile(yamlPath, tc.targetEnv)

			// Sort the results for consistent comparison
			sort.Strings(vars)
			sort.Strings(tc.expectedVars)

			if !reflect.DeepEqual(vars, tc.expectedVars) {
				t.Errorf("Expected variables %v, got %v", tc.expectedVars, vars)
			}

			if tc.shouldFindErrors && errs == nil {
				t.Error("Expected to find errors but none were reported")
			}

			if !tc.shouldFindErrors && errs != nil {
				t.Errorf("Expected no errors but found: %v", errs)
			}
		})
	}
}

func TestReadVariable(t *testing.T) {
	tests := []struct {
		name     string
		line     string
		expected string
	}{
		{
			name:     "Environment direct access with double quotes",
			line:     `username: <%= GitHub.environment["MYSQL_MYSQL1_RO_USER"].inspect %>`,
			expected: "MYSQL_MYSQL1_RO_USER",
		},
		{
			name:     "Environment direct access with single quotes",
			line:     `username: <%= GitHub.environment['MYSQL_MYSQL1_RO_USER'].inspect %>`,
			expected: "MYSQL_MYSQL1_RO_USER",
		},
		{
			name:     "Environment fetch with double quotes",
			line:     `host: <%= GitHub.environment.fetch("MYSQL_MYSQL1_READER_HOST").inspect %>`,
			expected: "MYSQL_MYSQL1_READER_HOST",
		},
		{
			name:     "Secrets fetch with double quotes",
			line:     `max_execution_time: <%= GitHub.secrets.fetch("NO_SECRETS_NUMBER") %>`,
			expected: "NO_SECRETS_NUMBER",
		},
		{
			name:     "Environment fetch with single quotes",
			line:     `host: <%= GitHub.environment.fetch('MYSQL_MYSQL1_READER_HOST').inspect %>`,
			expected: "MYSQL_MYSQL1_READER_HOST",
		},
		{
			name:     "Secrets fetch with single quotes",
			line:     `max_execution_time: <%= GitHub.secrets.fetch('NO_SECRETS_NUMBER') %>`,
			expected: "NO_SECRETS_NUMBER",
		},
		{
			name:     "Environment fetch with default value",
			line:     `max_execution_time: <%= GitHub.environment.fetch("MYSQL_MAX_EXECUTION_TIME", 0) %>`,
			expected: "MYSQL_MAX_EXECUTION_TIME",
		},
		{
			name:     "Secrets fetch with default value",
			line:     `max_execution_time: <%= GitHub.secrets.fetch("SECRETS_NUMBER", 0) %>`,
			expected: "SECRETS_NUMBER",
		},
		{
			name:     "No environment variable",
			line:     `max_execution_time: 30`,
			expected: "UNKNOWN_VARIABLE",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := readVariable(tc.line)
			if result != tc.expected {
				t.Errorf("Expected %q, got %q", tc.expected, result)
			}
		})
	}
}

func TestReadDotcomConfiguration(t *testing.T) {
	variables := readDotcomConfiguration(codespacesDatabaseYaml)

	if len(variables) == 0 {
		t.Error("No variables were found from parsing database.yml")
	}
}
