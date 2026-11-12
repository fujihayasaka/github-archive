// Package mcp provides functionality to fetch / filter MCP configuration from GitHub & identify MCP env vars
package mcp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"maps"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdAPITwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// ErrMCPConfiguration marks deterministic MCP config failures (invalid JSON, missing fields) as non-retriable.
var ErrMCPConfiguration = errors.New("MCP configuration error")

// ConfigProvider is satisfied by CustomAgent implementations that provide
// MCP server configuration. Not all agents have MCP config.
type ConfigProvider interface {
	MCPConfig() mcpconfig.JSON
}

// ConfigClient wraps the githubtwirp client and is used for fetching configuration from dotcom
type ConfigClient struct {
	ghTwirp githubtwirp.ClientInterface
}

// NewClient creates a new MCP client
func NewClient(ghTwirp githubtwirp.ClientInterface) *ConfigClient {
	return &ConfigClient{ghTwirp: ghTwirp}
}

// ConfigureParams represents the parameters required to get the MCP configuration for a repository and apply custom agent
type ConfigureParams struct {
	CustomAgent  sweagentd.CustomAgent
	FFClient     featureflags.Client
	GHTwirp      githubtwirp.ClientInterface
	RepositoryID int64
	UserID       int64

	// UsePreStartedPlaywright rewrites the Playwright MCP server entry from local/stdio
	// to a remote HTTP endpoint when a pre-started instance is available (custom image).
	UsePreStartedPlaywright bool
	// PreStartedPlaywrightURL is the HTTP endpoint URL for the pre-started Playwright instance.
	PreStartedPlaywrightURL string
}

// ConfigureResponse represents the encoded MCP configuration and whether 3P MCP policy is enabled
type ConfigureResponse struct {
	Encoded     string
	Enabled     bool
	Permissions permissions.Permissions
}

// ServerConfigEnvVar is the environment variable name the actions workflow expects for the MCP configuration JSON
const ServerConfigEnvVar = "GITHUB_COPILOT_MCP_JSON"

// InteractionIDEnvVar is the environment variable name the actions workflow expects for the interaction ID
const InteractionIDEnvVar = "GITHUB_COPILOT_INTERACTION_ID"

// PermissionsInputName is the name of the input the actions workflow expects for the GitHub token permissions
const PermissionsInputName = "COPILOT_AGENT_PERMISSIONS"

const configJSONLengthLimit = 13107

// Configure fetches the MCP configuration for the given repository and user, applies any custom agent configuration, and returns the encoded configuration
func Configure(ctx context.Context, params ConfigureParams) (ConfigureResponse, error) {
	resp, err := params.GHTwirp.SweagentdAPI().MCPConfigurationForRepository(ctx, &sweagentdAPITwirp.MCPConfigurationForRepositoryRequest{
		RepositoryId: uint64(params.RepositoryID),
		UserId:       uint64(params.UserID),
	})
	if err != nil {
		return ConfigureResponse{}, goerrors.Errorf("failed to get MCP configuration from dotcom: %w", err)
	}

	if !resp.IsMcpEnabled {
		return ConfigureResponse{
			Encoded:     "",
			Enabled:     false,
			Permissions: permissions.Unset,
		}, nil
	}

	cfg, err := parseConfig(resp.McpConfigurationJson)
	if err != nil {
		return ConfigureResponse{}, goerrors.Errorf("failed to parse MCP configuration: %w", errors.Join(ErrMCPConfiguration, err))
	}

	// Apply any MCP configuration from the custom agent (if provided), overwrites if the server already exists
	if p, ok := params.CustomAgent.(ConfigProvider); ok {
		maps.Copy(cfg.Servers, p.MCPConfig().Servers)
	}

	// Rewrite Playwright to use pre-started remote instance when available (custom image).
	// If no playwright entry exists, add one so the runtime uses the pre-started
	// instance instead of installing locally. If an entry exists and is local/stdio,
	// rewrite it. If it's already remote (e.g. with custom headers/OIDC), leave it unchanged.
	if params.UsePreStartedPlaywright && params.PreStartedPlaywrightURL != "" {
		pw, ok := cfg.Servers["playwright"]
		if !ok || mcpconfig.IsLocal(pw.Type) {
			tools := pw.Tools
			if len(tools) == 0 {
				tools = []string{"*"}
			}
			cfg.Servers["playwright"] = mcpconfig.Server{
				Tools: tools,
				Type:  "http",
				Remote: &mcpconfig.Remote{
					Type: "http",
					URL:  params.PreStartedPlaywrightURL,
				},
			}
		}
	}

	encoded, err := encodeConfig(cfg)
	if err != nil {
		return ConfigureResponse{}, goerrors.Errorf("failed to encode MCP configuration: %w", errors.Join(ErrMCPConfiguration, err))
	}

	perms := permissions.Unset
	if params.FFClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentRepoConfigCustomPermissions, params.UserID, params.RepositoryID) && cfg.GitHub != nil {
		perms = permissions.New(cfg.GitHub.Permissions)
		err := perms.Validate()
		if err != nil {
			return ConfigureResponse{}, goerrors.Errorf("invalid GitHub permissions in MCP configuration: %w", errors.Join(ErrMCPConfiguration, err))
		}
	}

	return ConfigureResponse{
		Encoded:     encoded,
		Enabled:     true,
		Permissions: perms,
	}, nil
}

// parseConfig parses the MCP configuration JSON string into the MCP JSON struct
func parseConfig(configStr string) (mcpconfig.JSON, error) {
	if configStr == "" {
		// This covers the case in which the MCP repository settings have never been saved
		// After first save the value will be at least {"mcpServers":{}}
		configStr = `{"mcpServers":{}}`
	}

	var cfg mcpconfig.JSON
	err := json.Unmarshal([]byte(configStr), &cfg)
	if err != nil {
		return mcpconfig.JSON{}, goerrors.Errorf("failed to parse base MCP configuration JSON: %w", err)
	}

	if cfg.Servers == nil {
		cfg.Servers = make(map[string]mcpconfig.Server)
	} else {
		for _, server := range cfg.Servers {
			if server.Tools == nil {
				return mcpconfig.JSON{}, goerrors.Errorf(
					"failed to parse base MCP configuration JSON: %w", mcpconfig.ErrToolsFieldIsRequired)
			}
		}
	}

	return cfg, nil
}

// encodeConfig encodes the MCP configuration as a base64 string since the actions workflow expects it that way
func encodeConfig(cfg mcpconfig.JSON) (string, error) {
	marshaledConfig, err := json.Marshal(cfg)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal MCP configuration: %w", err)
	}

	encoded := base64.StdEncoding.EncodeToString(marshaledConfig)
	if len(encoded) > configJSONLengthLimit {
		return "", goerrors.Errorf("length of base64 encoded MCP configuration JSON: %d exceeds maximum: %d", len(encoded), configJSONLengthLimit)
	}

	return encoded, nil
}
