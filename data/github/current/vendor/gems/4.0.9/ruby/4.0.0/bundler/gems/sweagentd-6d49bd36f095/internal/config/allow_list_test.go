package config

import (
	"compress/gzip"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	yaml "gopkg.in/yaml.v3"
)

func TestDefaultAllowList(t *testing.T) {
	rulesetYaml, err := GenerateEncodedDefaultRulesSetEnv()
	require.NoError(t, err)

	// Decode and ungzip the list to verify it contains the expected domains
	decoded, err := base64.StdEncoding.DecodeString(rulesetYaml)
	require.NoError(t, err)
	reader, err := gzip.NewReader(strings.NewReader(string(decoded)))
	require.NoError(t, err)
	defer reader.Close()
	uncompressed, err := io.ReadAll(reader)
	require.NoError(t, err)
	rulesetYaml = string(uncompressed)

	// Validate against schema
	schema := RulesFilesYamlSchema(t)
	var ruleData any
	err = yaml.Unmarshal(uncompressed, &ruleData)
	require.NoError(t, err)
	bytes, err := json.Marshal(ruleData)
	require.NoError(t, err)
	validationErrors, err := schema.ValidateBytes(context.Background(), bytes)
	if err != nil {
		t.Errorf("Validation failed for %s: %v", rulesetYaml, err)
	}

	if len(validationErrors) > 0 {
		t.Errorf("Validation errors for %s: %v", rulesetYaml, validationErrors)
	}

	// Test that essential domains are present
	essentialDomains := []string{
		// Package Managers
		"npmjs.org",
		"pypi.org",
		"rubygems.org",
		"gradle.org",
		"crates.io",
		"proxy.golang.org",
		// Build Essentials
		"nodejs.org",
		"yarnpkg.com",
		"registry.yarnpkg.com",
		"adoptium.net",
		"sh.rustup.rs",
		"quay.io",
		"mcr.microsoft.com",
		"gcr.io",
		"releases.hashicorp.com",

		// GitHub MCP Registry
		"api.mcp.github.com",

		// Linux Package Managers
		"archive.ubuntu.com",
		"deb.debian.org",
		"dl.fedoraproject.org",
		"mirror.centos.org",
		"dl-cdn.alpinelinux.org",
		"mirror.archlinux.org",
		"download.opensuse.org",
		"cdn.redhat.com",

		// Database Tools
		"binaries.prisma.sh",
	}

	for _, domain := range essentialDomains {
		assert.Contains(t, rulesetYaml, fmt.Sprintf("domain: %s", domain), "Default allow list should contain %s", domain)
	}
}

func TestGenerateRequiredFirewallAllowList_Dotcom(t *testing.T) {
	cfg := &Config{
		GitHubServerURL:     "https://github.com",
		CopilotAPIURL:       "https://api.githubcopilot.com",
		AgentCallbackURL:    "https://test-callback.com",
		GitHubAdvisoriesURL: "https://api.github.com/advisories",
	}

	list := GenerateRequiredFirewallAllowList(cfg)

	assert.Contains(t, list, "localhost")
	assert.Contains(t, list, "github.com")
	assert.Contains(t, list, "githubusercontent.com")
	assert.Contains(t, list, "test-callback.com")
	assert.Contains(t, list, "https://api.github.com/advisories")
	assert.Contains(t, list, "https://api.github.com/copilot_internal/user")
	assert.Contains(t, list, "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/")
	assert.Contains(t, list, "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/compare/")
	assert.Contains(t, list, "https://api.github.com/embeddings/code/search")
	assert.NotContains(t, list, "https://uploads.<tenant>.ghe.com/user-attachments/assets,https://api.<tenant>.ghe.com/internal/user-attachments/assets,")
	assert.NotContains(t, list, "copilot-telemetry-service", "Proxima telemetry endpoint should not be in dotcom allow list")
	// Verify GitHub Actions artifact storage accounts are present
	assert.Contains(t, list, "productionresultssa0.blob.core.windows.net")
	assert.Contains(t, list, "productionresultssa15.blob.core.windows.net")
	assert.Contains(t, list, "productionresultssa19.blob.core.windows.net")
}

func TestGenerateRequiredFirewallAllowList_Development(t *testing.T) {
	cfg := &Config{Environment: EnvironmentDevelopment}
	list := GenerateRequiredFirewallAllowList(cfg)
	assert.Contains(t, list, "localhost")
}

func TestGenerateRequiredFirewallAllowList_Proxima(t *testing.T) {
	cfg := &Config{
		GitHubServerURL:     "https://github.com",
		CopilotAPIURL:       "https://api.githubcopilot.com",
		AgentCallbackURL:    "https://test-callback.com",
		SecretScanningURL:   "https://scanning-api.<tenant>.ghe.com/api/v1/scan/multipart",
		GitHubAdvisoriesURL: "https://api.<tenant>.ghe.com/advisories",
		Environment:         EnvironmentProxima,
	}
	list := GenerateRequiredFirewallAllowList(cfg)
	assert.Contains(t, list, "https://uploads.<tenant>.ghe.com/user-attachments/assets,https://api.<tenant>.ghe.com/internal/user-attachments/assets,")
	assert.Contains(t, list, "https://api.<tenant>.ghe.com/copilot_internal/user")
	assert.Contains(t, list, "https://scanning-api.<tenant>.ghe.com/api/v1/scan/multipart,")
	assert.Contains(t, list, "https://api.<tenant>.ghe.com/advisories")
	assert.Contains(t, list, "localhost")
	assert.Contains(t, list, "github.com")
	assert.Contains(t, list, "githubusercontent.com")
	assert.Contains(t, list, "test-callback.com")
	assert.Contains(t, list, "objects-origin.<tenant>.ghe.com")
	assert.Contains(t, list, "https://copilot-telemetry-service.<tenant>.ghe.com")
	// Ensure there is no trailing comma
	assert.NotContains(t, list, ",,", "Allow list should not contain empty entries")
}

func TestGenerateRequiredFirewallAllowList_NoAsterisksInPaths(t *testing.T) {
	// The firewall schema only allows [a-zA-Z0-9/\-_]+ in URL paths.
	// Asterisks are not valid wildcards in paths - the firewall uses prefix matching instead.
	// Note: Subdomain wildcards like "*.example.com" are valid and handled separately.
	cfg := &Config{
		GitHubServerURL:     "https://github.com",
		CopilotAPIURL:       "https://api.githubcopilot.com",
		AgentCallbackURL:    "https://test-callback.com",
		GitHubAdvisoriesURL: "https://api.github.com/advisories",
	}

	list := GenerateRequiredFirewallAllowList(cfg)

	for rawURL := range strings.SplitSeq(list, ",") {
		rawURL = strings.TrimSpace(rawURL)
		if rawURL == "" {
			continue
		}

		// Parse the URL to check only the path portion
		parsed, err := url.Parse(rawURL)
		if err != nil {
			// Skip URLs that can't be parsed (e.g., bare domains, IPs)
			continue
		}

		// Check that the path doesn't contain asterisks
		assert.NotContains(t, parsed.Path, "*",
			"Firewall URL path should not contain asterisk wildcards (use prefix matching instead): %s", rawURL)
	}
}
