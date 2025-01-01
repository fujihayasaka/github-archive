package aqueduct

import (
	"testing"
)

type MockAqueductClient struct {
	Config *Config
}

func (m *MockAqueductClient) GetConfig() *Config {
	return m.Config
}

func TestNewAqueductClient(t *testing.T) {
	cfg := &Config{
		Addr:          "http://localhost:28085",
		AppName:       "",
		APIKey:        "AQUEDUCT_API_KEY",
		APIKeyVersion: 0,
	}

	client, err := NewAqueductClient(cfg)
	if err != nil {
		t.Fatalf("Error creating Aqueduct client: %v", err)
	}

	if client.GetConfig() != cfg {
		t.Errorf("Client configuration does not match the expected configuration")
	}
}
