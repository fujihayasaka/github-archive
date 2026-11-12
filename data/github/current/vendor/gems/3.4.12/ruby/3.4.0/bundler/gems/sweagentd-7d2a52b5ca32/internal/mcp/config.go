// Package mcp provides functionality to fetch / filter MCP configuration from GitHub & identify MCP env vars
package mcp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"maps"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdAPITwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

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
	RepositoryID int64
	UserID       int64
	CustomAgent  sweagentd.CustomAgent
	GHTwirp      githubtwirp.ClientInterface
}

// ConfigureResponse represents the encoded MCP configuration and whether 3P MCP policy is enabled
type ConfigureResponse struct {
	Encoded string
	Enabled bool
}

// ServerConfigEnvVar is the environment variable name the actions workflow expects for the MCP configuration JSON
const ServerConfigEnvVar = "GITHUB_COPILOT_MCP_JSON"

// InteractionIDEnvVar is the environment variable name the actions workflow expects for the interaction ID
const InteractionIDEnvVar = "GITHUB_COPILOT_INTERACTION_ID"

const configJSONLengthLimit = 13107

// Configure fetches the MCP configuration for the given repository and user, applies any custom agent configuration, and returns the encoded configuration
func Configure(ctx context.Context, params ConfigureParams) (ConfigureResponse, error) {
	resp, err := params.GHTwirp.SweagentdAPI().MCPConfigurationForRepository(ctx, &sweagentdAPITwirp.MCPConfigurationForRepositoryRequest{
		RepositoryId: uint64(params.RepositoryID),
		UserId:       uint64(params.UserID),
	})
	if err != nil {
		return ConfigureResponse{}, fmt.Errorf("failed to get MCP configuration from dotcom: %w", err)
	}

	if !resp.IsMcpEnabled {
		return ConfigureResponse{
			Encoded: "",
			Enabled: false,
		}, nil
	}

	cfg, err := parseConfig(resp.McpConfigurationJson)
	if err != nil {
		return ConfigureResponse{}, fmt.Errorf("failed to parse MCP configuration: %w", err)
	}

	// Apply any MCP configuration from the custom agent (if provided), overwrites if the server already exists
	maps.Copy(cfg.Servers, params.CustomAgent.MCPConfig().Servers)

	encoded, err := encodeConfig(cfg)
	if err != nil {
		return ConfigureResponse{}, fmt.Errorf("failed to encode MCP configuration: %w", err)
	}

	return ConfigureResponse{
		Encoded: encoded,
		Enabled: true,
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
		return mcpconfig.JSON{}, fmt.Errorf("failed to parse base MCP configuration JSON: %w", err)
	}

	if cfg.Servers == nil {
		cfg.Servers = make(map[string]mcpconfig.Server)
	}

	return cfg, nil
}

// encodeConfig encodes the MCP configuration as a base64 string since the actions workflow expects it that way
func encodeConfig(cfg mcpconfig.JSON) (string, error) {
	marshaledConfig, err := json.Marshal(cfg)
	if err != nil {
		return "", fmt.Errorf("failed to marshal MCP configuration: %w", err)
	}

	encoded := base64.StdEncoding.EncodeToString(marshaledConfig)
	if len(encoded) > configJSONLengthLimit {
		return "", fmt.Errorf("length of base64 encoded MCP configuration JSON: %d exceeds maximum: %d", len(encoded), configJSONLengthLimit)
	}

	return encoded, nil
}
