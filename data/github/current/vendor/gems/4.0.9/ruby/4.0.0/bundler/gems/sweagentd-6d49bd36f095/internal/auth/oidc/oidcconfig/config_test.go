package oidcconfig

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseConfig(t *testing.T) {
	t.Run("parses all fields", func(t *testing.T) {
		data := []byte(`{
			"oidcConfig": [{
				"secretSuffix": "MY_SECRET",
				"audience": "aud-123",
				"scope": "read:data write:data",
				"resource": "https://api.example.com",
				"client": "my-client-id",
				"grantType": "client_credentials",
				"endpoints": {
					"exchange": "https://example.com/token",
					"revoke": "https://example.com/revoke",
					"failure": "https://example.com/failure",
					"base": "https://auth.example.com"
				},
				"agentOnlySubject": true,
				"publicClient": true,
				"redirectPort": 8080
			}]
		}`)

		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		require.Len(t, cfg.OIDCConfig, 1)

		e := cfg.OIDCConfig[0]
		assert.Equal(t, "MY_SECRET", e.SecretSuffix)
		assert.Equal(t, "aud-123", e.Audience)
		assert.Equal(t, "read:data write:data", e.Scope)
		assert.Equal(t, "https://api.example.com", e.Resource)
		assert.Equal(t, "my-client-id", e.ClientID)
		assert.Equal(t, GrantTypeClientCredentials, e.GrantType)
		assert.Equal(t, "https://example.com/token", e.Endpoints.Exchange)
		assert.Equal(t, "https://example.com/revoke", e.Endpoints.Revoke)
		assert.Equal(t, "https://example.com/failure", e.Endpoints.Failure)
		assert.Equal(t, "https://auth.example.com", e.Endpoints.Base)
		assert.True(t, e.AgentOnlySubject)
		assert.True(t, e.IsPublicClient())
		assert.Equal(t, 8080, e.RedirectPort)
	})

	t.Run("optional fields default to zero values", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c"}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)

		e := cfg.OIDCConfig[0]
		assert.Empty(t, e.Scope)
		assert.Empty(t, e.Resource)
		assert.Empty(t, e.ClientID)
		assert.Empty(t, e.GrantType)
		assert.Empty(t, e.Endpoints.Exchange)
		assert.Empty(t, e.Endpoints.Revoke)
		assert.Empty(t, e.Endpoints.Failure)
		assert.Empty(t, e.Endpoints.Base)
		assert.False(t, e.AgentOnlySubject)
		assert.True(t, e.IsPublicClient())
		assert.Zero(t, e.RedirectPort)
		assert.False(t, e.UseClientCredentials())
	})

	t.Run("multiple entries", func(t *testing.T) {
		data := []byte(`{
			"oidcConfig": [
				{"secretSuffix": "A", "audience": "a"},
				{"secretSuffix": "B", "audience": "b"}
			]
		}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Len(t, cfg.OIDCConfig, 2)
	})

	t.Run("sets config source on all entries", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c"}]}`)

		cfg, err := ParseConfig(data, ConfigSourceAgenticApp)
		require.NoError(t, err)
		assert.Equal(t, "GITHUB_AGENTIC_APP_OIDC_S", cfg.OIDCConfig[0].FullSecretName())

		cfg, err = ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Equal(t, "GITHUB_COPILOT_OIDC_S", cfg.OIDCConfig[0].FullSecretName())
	})

	t.Run("accepts token exchange grant type", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "grantType": "urn:ietf:params:oauth:grant-type:token-exchange"}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Equal(t, GrantTypeTokenExchange, cfg.OIDCConfig[0].GrantType)
		assert.False(t, cfg.OIDCConfig[0].UseClientCredentials())
		assert.False(t, cfg.OIDCConfig[0].UseJWTBearer())
	})

	t.Run("accepts jwt-bearer grant type", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "grantType": "urn:ietf:params:oauth:grant-type:jwt-bearer"}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Equal(t, GrantTypeJWTBearer, cfg.OIDCConfig[0].GrantType)
		assert.True(t, cfg.OIDCConfig[0].UseJWTBearer())
		assert.False(t, cfg.OIDCConfig[0].UseClientCredentials())
	})

	t.Run("scopes is an alias for scope in JSON", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "a", "scopes": "read:data write:data"}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Equal(t, "read:data write:data", cfg.OIDCConfig[0].Scope)
	})

	t.Run("scope takes precedence over scopes in JSON", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "a", "scope": "primary", "scopes": "secondary"}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.Equal(t, "primary", cfg.OIDCConfig[0].Scope)
	})

	t.Run("publicClient false overrides default", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "a", "publicClient": false}]}`)
		cfg, err := ParseConfig(data, ConfigSourceSettings)
		require.NoError(t, err)
		assert.False(t, cfg.OIDCConfig[0].IsPublicClient())
	})

	// -- Validation errors --

	t.Run("rejects invalid JSON", func(t *testing.T) {
		_, err := ParseConfig([]byte(`not json`), ConfigSourceSettings)
		require.Error(t, err)
	})

	t.Run("rejects empty oidcConfig", func(t *testing.T) {
		_, err := ParseConfig([]byte(`{"oidcConfig": []}`), ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects missing secretSuffix", func(t *testing.T) {
		_, err := ParseConfig([]byte(`{"oidcConfig": [{"audience": "a"}]}`), ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects duplicate secretSuffix", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [
			{"secretSuffix": "DUP", "audience": "a"},
			{"secretSuffix": "DUP", "audience": "b"}
		]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects invalid exchange URL", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "endpoints": {"exchange": "://bad"}}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects invalid revoke URL", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "endpoints": {"revoke": "://bad"}}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects invalid failure URL", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "endpoints": {"failure": "://bad"}}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects invalid base URL", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "endpoints": {"base": "://bad"}}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects unsupported grant type", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "grantType": "bogus"}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects negative redirectPort", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "redirectPort": -1}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})

	t.Run("rejects redirectPort greater than 65535", func(t *testing.T) {
		data := []byte(`{"oidcConfig": [{"secretSuffix": "S", "audience": "c", "redirectPort": 65536}]}`)
		_, err := ParseConfig(data, ConfigSourceSettings)
		assert.ErrorIs(t, err, ErrInvalidConfig)
	})
}

func TestConfigEntry(t *testing.T) {
	t.Run("NewConfigEntry sets settings source", func(t *testing.T) {
		e := NewConfigEntry(ConfigEntry{SecretSuffix: "S"})
		assert.Equal(t, "GITHUB_COPILOT_OIDC_S", e.FullSecretName())
		assert.Empty(t, e.ServerName())
	})

	t.Run("NewConfigEntryForAgenticApp sets app source", func(t *testing.T) {
		e := NewConfigEntryForAgenticApp(ConfigEntry{SecretSuffix: "S"})
		assert.Equal(t, "GITHUB_AGENTIC_APP_OIDC_S", e.FullSecretName())
		assert.Empty(t, e.ServerName())
	})

	t.Run("NewConfigEntryForMCP sets MCP source, server name, and server URL, ignores suffix", func(t *testing.T) {
		e := NewConfigEntryForMCP("my-server", "https://example.com/mcp", ConfigEntry{SecretSuffix: "S"})
		assert.Equal(t, "", e.FullSecretName())
		assert.Equal(t, "my-server", e.ServerName())
		assert.Equal(t, "https://example.com/mcp", e.ServerURL())
	})

	t.Run("UseClientCredentials", func(t *testing.T) {
		assert.True(t, (&ConfigEntry{GrantType: GrantTypeClientCredentials}).UseClientCredentials())
		assert.False(t, (&ConfigEntry{GrantType: GrantTypeTokenExchange}).UseClientCredentials())
		assert.False(t, (&ConfigEntry{GrantType: GrantTypeJWTBearer}).UseClientCredentials())
		assert.False(t, (&ConfigEntry{}).UseClientCredentials())
	})

	t.Run("UseJWTBearer", func(t *testing.T) {
		assert.True(t, (&ConfigEntry{GrantType: GrantTypeJWTBearer}).UseJWTBearer())
		assert.False(t, (&ConfigEntry{GrantType: GrantTypeTokenExchange}).UseJWTBearer())
		assert.False(t, (&ConfigEntry{GrantType: GrantTypeClientCredentials}).UseJWTBearer())
		assert.False(t, (&ConfigEntry{}).UseJWTBearer())
	})

	t.Run("Validate accepts valid grant types", func(t *testing.T) {
		assert.NoError(t, (&ConfigEntry{GrantType: ""}).Validate())
		assert.NoError(t, (&ConfigEntry{GrantType: GrantTypeTokenExchange}).Validate())
		assert.NoError(t, (&ConfigEntry{GrantType: GrantTypeClientCredentials}).Validate())
		assert.NoError(t, (&ConfigEntry{GrantType: GrantTypeJWTBearer}).Validate())
	})
}

func TestSecretNameHelpers(t *testing.T) {
	t.Run("ParseSecretNameSuffix strips known prefixes", func(t *testing.T) {
		assert.Equal(t, "TOKEN", ParseSecretNameSuffix("GITHUB_COPILOT_OIDC_TOKEN"))
		assert.Equal(t, "TOKEN", ParseSecretNameSuffix("GITHUB_AGENTIC_APP_OIDC_TOKEN"))
	})

	t.Run("ParseSecretNameSuffix returns input for unknown prefix", func(t *testing.T) {
		assert.Equal(t, "OTHER_TOKEN", ParseSecretNameSuffix("OTHER_TOKEN"))
	})

	t.Run("IsValidSecretName accepts known prefixes", func(t *testing.T) {
		assert.True(t, IsValidSecretName("GITHUB_COPILOT_OIDC_TOKEN"))
		assert.True(t, IsValidSecretName("GITHUB_AGENTIC_APP_OIDC_TOKEN"))
	})

	t.Run("IsValidSecretName rejects unknown prefixes", func(t *testing.T) {
		assert.False(t, IsValidSecretName("OTHER_TOKEN"))
		assert.False(t, IsValidSecretName(""))
	})
}
