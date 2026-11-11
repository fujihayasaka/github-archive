package mcp

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestIsMCPVariable(t *testing.T) {
	tests := []struct {
		name         string
		variableName string
		expected     bool
	}{
		{
			name:         "valid MCP variable - simple",
			variableName: "COPILOT_MCP_SERVER1",
			expected:     true,
		},
		{
			name:         "valid MCP variable - with underscores",
			variableName: "COPILOT_MCP_MY_SERVER_CONFIG",
			expected:     true,
		},
		{
			name:         "valid MCP variable - with numbers",
			variableName: "COPILOT_MCP_SERVER123",
			expected:     true,
		},
		{
			name:         "valid MCP variable - mixed case (should match)",
			variableName: "COPILOT_MCP_ServerConfig",
			expected:     true,
		},
		{
			name:         "invalid - wrong prefix",
			variableName: "GITHUB_MCP_SERVER",
			expected:     false,
		},
		{
			name:         "invalid - missing MCP",
			variableName: "COPILOT_SERVER",
			expected:     false,
		},
		{
			name:         "invalid - empty string",
			variableName: "",
			expected:     false,
		},
		{
			name:         "invalid - contains spaces",
			variableName: "COPILOT_MCP_SERVER CONFIG",
			expected:     false,
		},
		{
			name:         "invalid - contains hyphens",
			variableName: "COPILOT_MCP_SERVER-CONFIG",
			expected:     false,
		},
		{
			name:         "invalid - contains special characters",
			variableName: "COPILOT_MCP_SERVER@CONFIG",
			expected:     false,
		},
		{
			name:         "valid - edge case with single character suffix",
			variableName: "COPILOT_MCP_A",
			expected:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsVar(tt.variableName)
			assert.Equal(t, tt.expected, result, "IsVar(%q) = %v, expected %v", tt.variableName, result, tt.expected)
		})
	}
}

func TestMCPVariableRegex(t *testing.T) {
	// Test the regex directly to ensure it's working as expected
	testCases := []string{
		"COPILOT_MCP_SERVER1",
		"COPILOT_MCP_MY_SERVER_CONFIG",
		"COPILOT_MCP_SERVER123",
		"COPILOT_MCP_A1B2C3",
	}

	for _, testCase := range testCases {
		matches := mcpVarRegex.FindStringSubmatch(testCase)
		assert.Len(t, matches, 2, "Expected regex to capture the suffix for %q", testCase)

		// The captured group should be the part after COPILOT_MCP_
		expectedSuffix := testCase[12:] // "COPILOT_MCP_" is 12 characters
		assert.Equal(t, expectedSuffix, matches[1], "Expected captured suffix to be %q for %q", expectedSuffix, testCase)
	}
}

func TestConstantsExist(t *testing.T) {
	// Test that our exported constants are defined correctly
	assert.NotEmpty(t, ServerConfigEnvVar, "ServerConfigEnvVar should be defined")
	assert.NotEmpty(t, InteractionIDEnvVar, "InteractionIDEnvVar should be defined")

	// Test that they have reasonable values (adjust these based on your actual constants)
	assert.Contains(t, ServerConfigEnvVar, "MCP", "ServerConfigEnvVar should contain 'MCP'")
	assert.Contains(t, InteractionIDEnvVar, "INTERACTION", "InteractionIDEnvVar should contain 'INTERACTION'")
}
