package config

import (
	"crypto/x509"
	"encoding/pem"
	"os"
	"testing"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfigBindAddress(t *testing.T) {
	t.Run("bind address is 0.0.0.0 in production", func(t *testing.T) {
		cfg := &Config{
			CommonConfig: config.CommonConfig{DeploymentEnvironment: "production"},
			Port:         9999,
		}
		addr := cfg.BindAddress()
		require.Equal(t, addr, "0.0.0.0:9999")
	})

	t.Run("bind address is 127.0.0.1 outside production", func(t *testing.T) {
		cfg := &Config{
			CommonConfig: config.CommonConfig{DeploymentEnvironment: "development"},
			Port:         9999,
		}
		addr := cfg.BindAddress()
		require.Equal(t, addr, "127.0.0.1:9999")
	})

}

func TestValidateConfig(t *testing.T) {
	t.Run("HMACKey must not be blank", func(t *testing.T) {
		cfg := &Config{
			HMACKeyList: "",
		}
		err := cfg.Validate()
		require.Error(t, err)
	})

	t.Run("HMACKey must not contain octocat in production", func(t *testing.T) {
		cfg := &Config{
			CommonConfig: config.CommonConfig{DeploymentEnvironment: "production"},
			HMACKeyList:  "octocat,othervalue",
		}
		err := cfg.Validate()
		require.Error(t, err)
	})

	t.Run("HMACKey must not be blank in any environment", func(t *testing.T) {
		cfg := &Config{
			CommonConfig: config.CommonConfig{DeploymentEnvironment: "development"},
			HMACKeyList:  "octocat",
		}
		err := cfg.Validate()
		require.NoError(t, err)
	})
}

func TestLoadTokenExchangeSigningKey(t *testing.T) {
	t.Run("returns error if file doesnt exist", func(t *testing.T) {
		cfg := &Config{
			TokenExchangeSigningKeyPath: "/not/a/file",
		}
		require.Error(t, cfg.LoadTokenExchangeSigningKey())
	})

	t.Run("errors when parsing bad data", func(t *testing.T) {
		cfg := &Config{}
		require.Error(t, cfg.parseTokenExchangeSigningKey([]byte("bad data")))
	})

	for _, deployEnv := range []string{"development", "test"} {
		t.Run("parses key successfully in "+deployEnv, func(t *testing.T) {
			tmpFile, err := os.CreateTemp(t.TempDir(), "test-token-exchange-key-*.pem")
			require.NoError(t, err)

			privateKey := crypto.MustCreateECDSAPrivateKey()
			privateKeyBytes, err := x509.MarshalECPrivateKey(privateKey)
			require.NoError(t, err)
			require.NotEmpty(t, privateKeyBytes)

			err = pem.Encode(tmpFile, &pem.Block{
				Type:  "EC PRIVATE KEY",
				Bytes: privateKeyBytes,
			})
			require.NoError(t, err)
			tmpFile.Close()

			cfg := &Config{
				CommonConfig: config.CommonConfig{
					DeploymentEnvironment: deployEnv,
				},
				TokenExchangeSigningKeyPath: tmpFile.Name(),
			}
			require.NoError(t, cfg.LoadTokenExchangeSigningKey())
			assert.NotNil(t, cfg.TokenExchangeSigningKey)
		})
	}

	for _, deployEnv := range []string{"production", "development", "test"} {
		t.Run("prefers and parses env correctly in "+deployEnv, func(t *testing.T) {
			cfg := &Config{
				CommonConfig: config.CommonConfig{
					DeploymentEnvironment: deployEnv,
				},
				// vault secrets are created from files with newlines replaced by '\n'
				TokenExchangeSigningKeyContents: "-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIPCoA8EVIv1K2yo1HRizrKISjEGZdy6xP9VsqY46aaG/oAoGCCqGSM49\nAwEHoUQDQgAEotbiZ+PVrJ1W+Z1mH509VY6edB2RWVk/gtoQID1sFAJId2scwcQ8\nSg05HYop/R7He4XVFX5cVMCFI33xUdoTrA==\n-----END EC PRIVATE KEY-----",
			}
			require.NoError(t, cfg.LoadTokenExchangeSigningKey())
			assert.NotNil(t, cfg.TokenExchangeSigningKey)
		})
	}
}
