package main

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"strings"

	"github.com/github/attester/pkg/auth"
	"github.com/github/attester/pkg/transport"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

type ErrAuthConfig struct {
	cfgField   string
	wrappedErr error
}

func (e ErrAuthConfig) Error() string {
	return fmt.Sprintf("failed to parse HMAC configs from %s: %s", e.cfgField, e.wrappedErr.Error())
}

// configStruct is the struct that holds the configuration for the application
type configStruct struct {
	APIPort                 string `mapstructure:"api-port"`
	AppEnv                  string `mapstructure:"app-env"`
	DogStatsdHost           string `mapstructure:"dogstatsd-host"`
	ReleaseHMACKey          string `mapstructure:"release-hmac-key"`
	ReleaseSecondaryHMACKey string `mapstructure:"release-secondary-hmac-key"`
	LogLevel                string `mapstructure:"log-level"`
	Stamp                   string `mapstructure:"stamp"`
	ReleaseAzureKeyVaultRef string `mapstructure:"release-azure-keyvault-ref"`
	ReleaseCertificatePath  string `mapstructure:"release-certificate-path"`
	ReleasePrivateKeyPath   string `mapstructure:"release-private-key-path"`
	TSAURL                  string `mapstructure:"tsa-url"`
}

func initConfig(cmd *cobra.Command, _ []string) {
	viper.SetEnvPrefix("ATTESTER")
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	err := viper.BindPFlags(cmd.Flags())
	cobra.CheckErr(err)

	if viper.GetString("config") != "" {
		viper.SetConfigFile(viper.GetString("config"))

		err := viper.ReadInConfig()
		cobra.CheckErr(err)
	}

	err = viper.Unmarshal(&config)
	cobra.CheckErr(err)
}

func buildHMACConfig(cfg *configStruct) (transport.ServerAuthConfig, error) {
	releaseCfg := auth.HMACKeys{cfg.ReleaseHMACKey, cfg.ReleaseSecondaryHMACKey}

	return transport.ServerAuthConfig{
		// TODO: add boo auth config
		Boo:     releaseCfg,
		Release: releaseCfg,
	}, nil
}

func loadCert(certPath string) ([]byte, error) {
	// Read the PEM certificate file
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate from %s: %w", certPath, err)
	}

	// Decode the PEM block
	block, rest := pem.Decode(certPEM)

	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block from certificate file")
	}

	if block.Type != "CERTIFICATE" {
		return nil, fmt.Errorf("unexpected PEM block type: %s", block.Type)
	}

	// Optionally, log if there is additional data
	if len(rest) > 0 {
		fmt.Println("Additional data found after the first PEM block")
	}

	// Parse the certificate using x509
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse certificate: %w", err)
	}

	// Return the certificate's raw DER bytes
	return cert.Raw, nil
}

func loadPrivateKey(keyPath string) (*ecdsa.PrivateKey, error) {
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read private key from %s: %w", keyPath, err)
	}

	// Decode the PEM block
	block, _ := pem.Decode(keyPEM)

	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block from key file")
	}

	if block.Type != "PRIVATE KEY" {
		return nil, fmt.Errorf("unexpected PEM block type: %s", block.Type)
	}

	privateKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse key: %w", err)
	}

	return privateKey.(*ecdsa.PrivateKey), nil
}

// parse command line flags and environment variables
func initServerCommand(runFn func(*cobra.Command, []string) error) *cobra.Command {
	var cmdServer = &cobra.Command{
		Use:              "server",
		Short:            "Run the Attester server",
		Long:             "Run the Attester server",
		PersistentPreRun: initConfig,
		RunE:             runFn,
	}

	cmdServer.Flags().StringP("api-port", "p", "8080", "API server port")
	cmdServer.Flags().StringP("app-env", "e", "production", "environment")
	cmdServer.Flags().StringP("config", "c", "", "provide a configuration file")
	cmdServer.Flags().String("log-level", "info", "logging verbosity: <debug, info>")
	cmdServer.Flags().String("release-hmac-key", "", "Release service HMAC key")
	cmdServer.Flags().String("release-secondary-hmac-key", "", "Release service secondary HMAC key")
	cmdServer.Flags().String("dogstatsd-host", "", "dogstatsd host")
	cmdServer.Flags().String("stamp", "", "Name of the stamp to use")
	cmdServer.Flags().String("release-azure-keyvault-ref", "", "Release service Azure Key Vault reference")
	cmdServer.Flags().String("tsa-url", "", "URL of the timestamp authority")
	cmdServer.Flags().String("release-certificate-path", "", "Path to the Release service certificate file")
	cmdServer.Flags().String("release-private-key-path", "", "Path to the Release service signing key file")

	return cmdServer
}
