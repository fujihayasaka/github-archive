package aqueduct

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/require"
)

type MockAqueductClient struct {
	Config *Config
}

func (m *MockAqueductClient) GetConfig() *Config {
	return m.Config
}

func getTestAqueductConfig(t *testing.T) *Config {
	aqueductCfg := &Config{}
	err := aqueductCfg.Load()
	require.NoError(t, err)

	aqueductAddress, err := utils.GetMinikubeIp()
	require.NoError(t, err)

	aqueductCfg.Addr = fmt.Sprintf("http://%s:28141", aqueductAddress)
	aqueductCfg.AppName = fmt.Sprintf("test-%d", time.Now().Unix())

	return aqueductCfg
}

func TestNewAqueductClient(t *testing.T) {
	ctx := context.Background()
	cfg := getTestAqueductConfig(t)

	client, err := NewAqueductClient(ctx, cfg)
	if err != nil {
		t.Fatalf("Error creating Aqueduct client: %v", err)
	}

	if client.GetConfig() != cfg {
		t.Errorf("Client configuration does not match the expected configuration")
	}
}
