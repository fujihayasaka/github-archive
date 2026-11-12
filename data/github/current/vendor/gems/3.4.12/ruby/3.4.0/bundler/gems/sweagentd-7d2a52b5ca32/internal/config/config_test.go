package config

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/observability"
	"github.com/qri-io/jsonschema"
	"github.com/stretchr/testify/require"
	yaml "gopkg.in/yaml.v3"
)

func TestLoad(t *testing.T) {
	// This is a basic sanity check that will fail if someone has accidentally
	// added private fields to the Config struct.
	_, err := Load()
	require.NoError(t, err)
}

func TestDefaultFirewallRules(t *testing.T) {
	cfg, err := Load()
	require.NoError(t, err)

	exporters := observability.NewNoopExporters()
	// This should extract the context-value field from the context
	logger := exporters.LoggerWithTelemetry(context.Background())

	cfg.PopulateFirewallConfiguration(logger)
	require.NoError(t, err)

	_, err = GenerateEncodedDefaultRulesSetEnv()
	require.NoError(t, err)
}

func TestValidateRulesAgainstSchema(t *testing.T) {
	// Read the schema file
	schema := RulesFilesYamlSchema(t)

	// Read all rule files
	rulesDir := "default_network_rules"
	entries, err := os.ReadDir(rulesDir)
	require.NoError(t, err)

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".rules.yaml") {
			continue
		}

		t.Run(entry.Name(), func(t *testing.T) {
			// Read rule file
			rulePath := filepath.Join(rulesDir, entry.Name())
			ruleBytes, err := os.ReadFile(rulePath)
			require.NoError(t, err)

			// Parse YAML to interface{}
			var ruleData interface{}
			err = yaml.Unmarshal(ruleBytes, &ruleData)
			require.NoError(t, err)

			bytes, err := json.Marshal(ruleData)
			require.NoError(t, err)

			// Validate against schema
			validationErrors, err := schema.ValidateBytes(context.Background(), bytes)
			if err != nil {
				t.Errorf("Validation failed for %s: %v", entry.Name(), err)
			}

			if len(validationErrors) > 0 {
				t.Errorf("Validation errors for %s: %v", entry.Name(), validationErrors)
			}
		})
	}
}

func RulesFilesYamlSchema(t *testing.T) *jsonschema.Schema {
	schemaPath := "firewallrule.schema.json"
	schemaBytes, err := os.ReadFile(schemaPath)
	require.NoError(t, err)

	// Create JSON schema validator
	schema := &jsonschema.Schema{}
	err = json.Unmarshal(schemaBytes, schema)
	require.NoError(t, err)
	return schema
}
