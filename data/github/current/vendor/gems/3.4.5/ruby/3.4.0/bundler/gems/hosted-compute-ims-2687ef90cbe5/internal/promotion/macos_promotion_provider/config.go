package macos_promotion_provider

import (
	"strings"

	"github.com/github/hosted-compute-ims/internal/models"
	mcpModels "github.com/github/maccloud-go-core/maccloud/generated/models"
)

type Config struct {
	// MCPAddrs is a comma separated list of addresses for the MCP service.
	MCPAddrs string `config:"http://maccloud-mcp:8088,env=MCP_ADDRS"`
	// MCPIssuer is the issuer to use when generating JWTs for the MCP service.
	MCPIssuer string `config:"hosted-compute-ims,env=MCP_ISSUER"`
}

func (c *Config) GetMCPAddrs() []string {
	return strings.Split(c.MCPAddrs, ",")
}

func ArchitectureToMCPArchitecture(architecture models.Architecture) mcpModels.Architecture {
	switch architecture {
	case "X64":
		return mcpModels.Architecture_X86_64
	case "Arm64":
		return mcpModels.Architecture_ARM64
	default:
		return mcpModels.Architecture_UNSPECIFIED_ARCHITECTURE
	}
}
