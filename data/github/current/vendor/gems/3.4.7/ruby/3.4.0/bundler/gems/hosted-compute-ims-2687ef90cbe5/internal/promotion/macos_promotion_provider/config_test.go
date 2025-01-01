package macos_promotion_provider

import (
	"testing"

	mcpModels "github.com/github/maccloud-go-core/maccloud/generated/models"
	"github.com/stretchr/testify/assert"
)

func TestMCPConfig(t *testing.T) {
	t.Run("GetMCPAddrs", func(t *testing.T) {
		c := Config{
			MCPAddrs: "http://maccloud-mcp:8088,http://maccloud-mcp:8089",
		}
		addrs := c.GetMCPAddrs()
		if len(addrs) != 2 {
			t.Errorf("expected 2 addrs, got %d", len(addrs))
		}
		assert.Equal(t, "http://maccloud-mcp:8088", addrs[0])
		assert.Equal(t, "http://maccloud-mcp:8089", addrs[1])
	})

	t.Run("ArchitectureToMCPArchitecture", func(t *testing.T) {
		arch := ArchitectureToMCPArchitecture("X64")
		assert.Equal(t, mcpModels.Architecture_X86_64, arch)

		arch = ArchitectureToMCPArchitecture("Arm64")
		assert.Equal(t, mcpModels.Architecture_ARM64, arch)

		arch = ArchitectureToMCPArchitecture("Invalid")
		assert.Equal(t, mcpModels.Architecture_UNSPECIFIED_ARCHITECTURE, arch)
	})
}
