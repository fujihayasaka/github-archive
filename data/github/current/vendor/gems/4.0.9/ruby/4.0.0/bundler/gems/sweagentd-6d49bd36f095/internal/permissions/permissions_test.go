package permissions

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewGitHubPermissions(t *testing.T) {
	tests := []struct {
		name     string
		input    any
		expected map[string]string
	}{
		{
			name:     "nil input returns empty permissions",
			input:    nil,
			expected: map[string]string{},
		},
		{
			name:  "read-all string returns all read permissions",
			input: "read-all",
			expected: map[string]string{
				"actions":         "read",
				"checks":          "read",
				"contents":        "read",
				"discussions":     "read",
				"issues":          "read",
				"metadata":        "read",
				"pull-requests":   "read",
				"security-events": "read",
			},
		},
		{
			name:  "write-all string returns all permissions with write where available",
			input: "write-all",
			expected: map[string]string{
				"actions":         "write",
				"checks":          "read",
				"contents":        "write",
				"discussions":     "write",
				"issues":          "write",
				"metadata":        "read",
				"pull-requests":   "write",
				"security-events": "read",
				"workflows":       "write",
			},
		},
		{
			name:     "unknown string returns empty permissions",
			input:    "unknown",
			expected: map[string]string{},
		},
		{
			name:     "empty map[string]string returns empty permissions",
			input:    map[string]string{},
			expected: map[string]string{},
		},
		{
			name: "map[string]string with values adds metadata read",
			input: map[string]string{
				"contents": "write",
				"issues":   "read",
			},
			expected: map[string]string{
				"contents": "write",
				"issues":   "read",
				"metadata": "read",
			},
		},
		{
			name:     "empty map[string]any returns empty permissions",
			input:    map[string]any{},
			expected: map[string]string{},
		},
		{
			name: "map[string]any with values adds metadata read",
			input: map[string]any{
				"contents": "write",
				"issues":   "read",
			},
			expected: map[string]string{
				"contents": "write",
				"issues":   "read",
				"metadata": "read",
			},
		},
		{
			name: "map[string]any with non-string values filters them out",
			input: map[string]any{
				"contents": "write",
				"issues":   123,
				"actions":  "read",
			},
			expected: map[string]string{
				"contents": "write",
				"actions":  "read",
				"metadata": "read",
			},
		},
		{
			name: "GitHubPermissions input returns same",
			input: Permissions{
				permissions: map[string]string{
					"contents": "write",
				},
			},
			expected: map[string]string{
				"contents": "write",
			},
		},
		{
			name:     "integer input returns empty permissions",
			input:    42,
			expected: map[string]string{},
		},
		{
			name: "camelCase keys in map[string]string get normalized",
			input: map[string]string{
				"pullRequests":   "write",
				"securityEvents": "read",
				"contents":       "read",
			},
			expected: map[string]string{
				"pull-requests":   "write",
				"security-events": "read",
				"contents":        "read",
				"metadata":        "read",
			},
		},
		{
			name: "camelCase keys in map[string]any get normalized",
			input: map[string]any{
				"pullRequests":   "write",
				"securityEvents": "read",
			},
			expected: map[string]string{
				"pull-requests":   "write",
				"security-events": "read",
				"metadata":        "read",
			},
		},
		{
			name: "mixed camelCase and dash-separated keys get normalized",
			input: map[string]string{
				"pullRequests": "write",
				"contents":     "read",
				"issues":       "write",
			},
			expected: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
				"issues":        "write",
				"metadata":      "read",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := New(tt.input)
			assert.Equal(t, tt.expected, result.permissions)
		})
	}
}

func TestGitHubPermissions_Validate(t *testing.T) {
	tests := []struct {
		name        string
		permissions map[string]string
		wantErr     error
	}{
		{
			name: "valid permissions",
			permissions: map[string]string{
				"actions":       "read",
				"contents":      "write",
				"issues":        "read",
				"metadata":      "read",
				"pull-requests": "write",
			},
			wantErr: nil,
		},
		{
			name: "valid permissions with none value",
			permissions: map[string]string{
				"actions":  "none",
				"contents": "read",
			},
			wantErr: nil,
		},
		{
			name: "invalid permission key",
			permissions: map[string]string{
				"invalid-permission": "read",
			},
			wantErr: ErrInvalidPermission,
		},
		{
			name: "invalid permission value",
			permissions: map[string]string{
				"contents": "invalid",
			},
			wantErr: ErrInvalidPermissionValue,
		},
		{
			name: "metadata with write should fail",
			permissions: map[string]string{
				"metadata": "write",
			},
			wantErr: ErrInvalidPermissionValue,
		},
		{
			name: "workflows with read should fail",
			permissions: map[string]string{
				"workflows": "read",
			},
			wantErr: ErrInvalidPermissionValue,
		},
		{
			name:        "empty permissions is valid",
			permissions: map[string]string{},
			wantErr:     nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := Permissions{permissions: tt.permissions}
			err := p.Validate()
			if tt.wantErr != nil {
				require.Error(t, err)
				assert.True(t, errors.Is(err, tt.wantErr))
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestGitHubPermissions_IsUnset(t *testing.T) {
	tests := []struct {
		name        string
		permissions map[string]string
		want        bool
	}{
		{
			name:        "empty permissions is unset",
			permissions: map[string]string{},
			want:        true,
		},
		{
			name:        "nil permissions is unset",
			permissions: nil,
			want:        true,
		},
		{
			name: "permissions with values is not unset",
			permissions: map[string]string{
				"contents": "read",
			},
			want: false,
		},
		{
			name: "permissions with metadata only is not unset",
			permissions: map[string]string{
				"metadata": "read",
			},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := Permissions{permissions: tt.permissions}
			assert.Equal(t, tt.want, p.IsUnset())
		})
	}
}

func TestGitHubPermissions_ToDotCom(t *testing.T) {
	tests := []struct {
		name        string
		permissions map[string]string
		expected    map[string]string
		wantErr     bool
	}{
		{
			name:        "empty permissions returns only metadata",
			permissions: map[string]string{},
			expected: map[string]string{
				"metadata": "read",
			},
			wantErr: false,
		},
		{
			name: "converts hyphens to underscores",
			permissions: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
			},
			expected: map[string]string{
				"pull_requests": "write",
				"contents":      "read",
				"metadata":      "read",
			},
			wantErr: false,
		},
		{
			name: "filters out none values",
			permissions: map[string]string{
				"actions":  "none",
				"contents": "write",
				"issues":   "none",
			},
			expected: map[string]string{
				"contents": "write",
				"metadata": "read",
			},
			wantErr: false,
		},
		{
			name: "always includes metadata read",
			permissions: map[string]string{
				"contents": "write",
			},
			expected: map[string]string{
				"contents": "write",
				"metadata": "read",
			},
			wantErr: false,
		},
		{
			name: "invalid permission returns error",
			permissions: map[string]string{
				"invalid": "read",
			},
			expected: nil,
			wantErr:  true,
		},
		{
			name: "invalid permission value returns error",
			permissions: map[string]string{
				"contents": "invalid",
			},
			expected: nil,
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := Permissions{permissions: tt.permissions}
			result, err := p.ToDotCom()
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func TestGitHubPermissions_ToMap(t *testing.T) {
	permissions := map[string]string{
		"contents": "write",
		"issues":   "read",
	}
	p := Permissions{permissions: permissions}
	result := p.ToMap()
	assert.Equal(t, permissions, result)
}

func TestResolvePermissions(t *testing.T) {
	tests := []struct {
		name          string
		agentProvided Permissions
		repoLevel     Permissions
		expected      Permissions
	}{
		{
			name:          "agent provided permissions are used when set",
			agentProvided: Permissions{permissions: map[string]string{"contents": "write"}},
			repoLevel:     Permissions{permissions: map[string]string{"contents": "read"}},
			expected:      Permissions{permissions: map[string]string{"contents": "write"}},
		},
		{
			name:          "repo level permissions used when agent provided is unset",
			agentProvided: Permissions{permissions: map[string]string{}},
			repoLevel:     Permissions{permissions: map[string]string{"contents": "read"}},
			expected:      Permissions{permissions: map[string]string{"contents": "read"}},
		},
		{
			name:          "default permissions used when both are unset",
			agentProvided: Permissions{permissions: map[string]string{}},
			repoLevel:     Permissions{permissions: map[string]string{}},
			expected:      Default,
		},
		{
			name:          "default permissions used when both are nil",
			agentProvided: Permissions{},
			repoLevel:     Permissions{},
			expected:      Default,
		},
		{
			name:          "agent provided empty map prefers repo level",
			agentProvided: Permissions{permissions: map[string]string{}},
			repoLevel:     Permissions{permissions: map[string]string{"actions": "write"}},
			expected:      Permissions{permissions: map[string]string{"actions": "write"}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ResolvePermissions(tt.agentProvided, tt.repoLevel)
			assert.Equal(t, tt.expected.permissions, result.ToMap())
		})
	}
}

func TestRestrictTriggeredMCPPermissions(t *testing.T) {
	tests := []struct {
		name     string
		input    Permissions
		expected map[string]string
	}{
		{
			name: "downscopes actions write and removes deployments",
			input: Permissions{
				permissions: map[string]string{
					"actions":     "write",
					"deployments": "write",
					"contents":    "write",
				},
			},
			expected: map[string]string{
				"actions":  "read",
				"contents": "write",
			},
		},
		{
			name: "preserves non-write actions values",
			input: Permissions{
				permissions: map[string]string{
					"actions": "none",
					"issues":  "write",
				},
			},
			expected: map[string]string{
				"actions": "none",
				"issues":  "write",
			},
		},
		{
			name: "removes deployments read",
			input: Permissions{
				permissions: map[string]string{
					"deployments": "read",
					"issues":      "write",
				},
			},
			expected: map[string]string{
				"issues": "write",
			},
		},
		{
			name: "handles unset permissions",
			input: Permissions{
				permissions: map[string]string{},
			},
			expected: map[string]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := RestrictTriggeredMCPPermissions(tt.input)
			assert.Equal(t, tt.expected, actual.ToMap())
		})
	}
}

func TestDefaultGitHubPermissions(t *testing.T) {
	// Verify the default permissions are set correctly
	expected := map[string]string{
		"actions":       "read",
		"contents":      "read",
		"discussions":   "read",
		"issues":        "read",
		"metadata":      "read",
		"pull-requests": "read",
	}
	assert.Equal(t, expected, Default.permissions)
}

func TestAllowedGitHubPermissions(t *testing.T) {
	// Verify all allowed permissions are present
	expected := []string{"actions", "checks", "contents", "discussions", "issues", "metadata", "pull-requests", "security-events", "workflows"}
	assert.Equal(t, expected, Allowed)
}

func TestAllowedGitHubPermissionValues(t *testing.T) {
	// Verify that all allowed permissions have their values defined
	for _, perm := range Allowed {
		values, exists := AllowedValues[perm]
		assert.True(t, exists, "permission %q should have allowed values", perm)
		assert.NotEmpty(t, values, "permission %q should have at least one allowed value", perm)
	}

	// Verify metadata only allows read
	assert.Equal(t, []string{"read"}, AllowedValues["metadata"])

	// Verify workflows doesn't allow read
	assert.NotContains(t, AllowedValues["workflows"], "read")
}

func TestCamelCaseToDash(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "already lowercase",
			input:    "contents",
			expected: "contents",
		},
		{
			name:     "already dash-separated",
			input:    "pull-requests",
			expected: "pull-requests",
		},
		{
			name:     "simple camelCase",
			input:    "pullRequests",
			expected: "pull-requests",
		},
		{
			name:     "camelCase with multiple words",
			input:    "securityEvents",
			expected: "security-events",
		},
		{
			name:     "single character",
			input:    "a",
			expected: "a",
		},
		{
			name:     "uppercase first letter",
			input:    "PullRequests",
			expected: "pull-requests",
		},
		{
			name:     "metadata",
			input:    "metadata",
			expected: "metadata",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := camelCaseToDash(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestNormalizePermissionKeys(t *testing.T) {
	tests := []struct {
		name     string
		input    map[string]string
		expected map[string]string
	}{
		{
			name:     "empty map",
			input:    map[string]string{},
			expected: map[string]string{},
		},
		{
			name: "camelCase keys",
			input: map[string]string{
				"pullRequests":   "write",
				"contents":       "read",
				"securityEvents": "read",
			},
			expected: map[string]string{
				"pull-requests":   "write",
				"contents":        "read",
				"security-events": "read",
			},
		},
		{
			name: "already dash-separated keys",
			input: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
			},
			expected: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
			},
		},
		{
			name: "mixed keys",
			input: map[string]string{
				"pullRequests": "write",
				"contents":     "read",
				"metadata":     "read",
			},
			expected: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
				"metadata":      "read",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := normalizePermissionKeys(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestPermissions_MarshalJSON(t *testing.T) {
	tests := []struct {
		name        string
		permissions Permissions
		expected    string
	}{
		{
			name:        "empty permissions",
			permissions: Permissions{permissions: map[string]string{}},
			expected:    `{}`,
		},
		{
			name: "permissions with dash-separated keys",
			permissions: Permissions{permissions: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
				"metadata":      "read",
			}},
			expected: `{"contents":"read","metadata":"read","pull-requests":"write"}`,
		},
		{
			name: "single permission",
			permissions: Permissions{permissions: map[string]string{
				"contents": "write",
			}},
			expected: `{"contents":"write"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := json.Marshal(tt.permissions)
			require.NoError(t, err)
			assert.JSONEq(t, tt.expected, string(data))
		})
	}
}

func TestPermissions_UnmarshalJSON(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		expected    map[string]string
		expectError bool
	}{
		{
			name:     "empty JSON object",
			input:    `{}`,
			expected: map[string]string{},
		},
		{
			name:  "dash-separated keys",
			input: `{"pull-requests":"write","contents":"read"}`,
			expected: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
			},
		},
		{
			name:  "camelCase keys get normalized",
			input: `{"pullRequests":"write","securityEvents":"read","contents":"write"}`,
			expected: map[string]string{
				"pull-requests":   "write",
				"security-events": "read",
				"contents":        "write",
			},
		},
		{
			name:  "mixed camelCase and dash-separated keys",
			input: `{"pullRequests":"write","contents":"read","security-events":"read"}`,
			expected: map[string]string{
				"pull-requests":   "write",
				"contents":        "read",
				"security-events": "read",
			},
		},
		{
			name:        "invalid JSON",
			input:       `{"invalid": json}`,
			expectError: true,
		},
		{
			name:        "non-string values",
			input:       `{"contents": 123}`,
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var p Permissions
			err := json.Unmarshal([]byte(tt.input), &p)

			if tt.expectError {
				require.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, p.permissions)
		})
	}
}

func TestPermissions_JSONRoundTrip(t *testing.T) {
	tests := []struct {
		name        string
		permissions map[string]string
	}{
		{
			name:        "empty permissions",
			permissions: map[string]string{},
		},
		{
			name: "dash-separated permissions",
			permissions: map[string]string{
				"pull-requests": "write",
				"contents":      "read",
				"metadata":      "read",
			},
		},
		{
			name: "single permission",
			permissions: map[string]string{
				"contents": "write",
			},
		},
		{
			name: "multiple permissions",
			permissions: map[string]string{
				"actions":         "read",
				"contents":        "write",
				"issues":          "write",
				"metadata":        "read",
				"pull-requests":   "write",
				"security-events": "read",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create original permissions
			original := Permissions{permissions: tt.permissions}

			// Marshal to JSON
			data, err := json.Marshal(original)
			require.NoError(t, err)

			// Unmarshal back to Permissions
			var roundtrip Permissions
			err = json.Unmarshal(data, &roundtrip)
			require.NoError(t, err)

			// Should be equal
			assert.Equal(t, original.permissions, roundtrip.permissions)
		})
	}
}

func TestPermissions_UnmarshalJSON_WithCamelCase(t *testing.T) {
	// Test that unmarshaling JSON with camelCase keys normalizes them
	jsonInput := `{
		"pullRequests": "write",
		"securityEvents": "read",
		"contents": "read"
	}`

	var p Permissions
	err := json.Unmarshal([]byte(jsonInput), &p)
	require.NoError(t, err)

	// Verify keys are normalized
	assert.Equal(t, "write", p.permissions["pull-requests"])
	assert.Equal(t, "read", p.permissions["security-events"])
	assert.Equal(t, "read", p.permissions["contents"])

	// Verify camelCase keys don't exist
	assert.NotContains(t, p.permissions, "pullRequests")
	assert.NotContains(t, p.permissions, "securityEvents")

	// Verify ToMap returns normalized keys
	permsMap := p.ToMap()
	assert.Contains(t, permsMap, "pull-requests")
	assert.Contains(t, permsMap, "security-events")
	assert.NotContains(t, permsMap, "pullRequests")
	assert.NotContains(t, permsMap, "securityEvents")
}
