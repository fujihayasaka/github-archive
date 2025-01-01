package main

import (
	"crypto"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/transport"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const mySQLDBConnFormat = "%s:%s@tcp(%s:%s)/%s?parseTime=true"

type ErrAuthConfig struct {
	cfgField   string
	wrappedErr error
}

func (e ErrAuthConfig) Error() string {
	return fmt.Sprintf("failed to parse HMAC configs from %s: %s", e.cfgField, e.wrappedErr.Error())
}

// configStruct is the struct that holds the configuration for the application
type configStruct struct {
	APIPort            string   `mapstructure:"api-port"`
	AppEnv             string   `mapstructure:"app-env"`
	AzureBlobAccount   string   `mapstructure:"azure-blob-account"`
	AzureBlobContainer string   `mapstructure:"azure-blob-container"`
	Backend            string   `mapstructure:"backend"`
	DogStatsdHost      string   `mapstructure:"dogstatsd-host"`
	DotcomAuthConfig   string   `mapstructure:"dotcom-auth-config"`
	KafkaBrokers       []string `mapstructure:"kafka-brokers"`
	KafkaClientID      string   `mapstructure:"kafka-client-id"`
	KafkaRootCA        string   `mapstructure:"kafka-root-ca"`
	LegacyAuthConfig   string   `mapstructure:"legacy-auth-config"`
	LogLevel           string   `mapstructure:"log-level"`
	MySQLDBConn        string
	MySQLDatabase      string `mapstructure:"mysql-database"`
	MySQLHost          string `mapstructure:"mysql-host"`
	MySQLPassword      string `mapstructure:"mysql-password"`
	MySQLPort          string `mapstructure:"mysql-port"`
	MySQLUser          string `mapstructure:"mysql-user"`
	MySQLRODBConn      string
	MySQLRODatabase    string `mapstructure:"mysql-ro-database"`
	MySQLROHost        string `mapstructure:"mysql-ro-host"`
	MySQLROPassword    string `mapstructure:"mysql-ro-password"`
	MySQLROPort        string `mapstructure:"mysql-ro-port"`
	MySQLROUser        string `mapstructure:"mysql-ro-user"`
	PkgReadAuthConfig  string `mapstructure:"pkg-read-auth-config"`
	PkgWriteAuthConfig string `mapstructure:"pkg-write-auth-config"`
	Stamp              string `mapstructure:"stamp"`
	TUFDirectory       string `mapstructure:"tuf-directory"`
	TUFMirror          string `mapstructure:"tuf-mirror"`
	TrustedKeys        string `mapstructure:"trusted-keys"`
	TrustedKeysParsed  map[string]crypto.PublicKey
}

func initConfig(cmd *cobra.Command, _ []string) {
	viper.SetEnvPrefix("TMA")
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

	initDatabaseConfig(&config)

	if config.TrustedKeys != "" {
		config.TrustedKeysParsed, err = attestation.ParseTrustedKeys(config.TrustedKeys)
		if err != nil {
			cobra.CheckErr(err)
		}
	}
}

func initDatabaseConfig(c *configStruct) {
	c.MySQLDBConn = fmt.Sprintf(mySQLDBConnFormat,
		c.MySQLUser,
		c.MySQLPassword,
		c.MySQLHost,
		c.MySQLPort,
		c.MySQLDatabase)

	if c.MySQLRODatabase != "" &&
		c.MySQLROHost != "" &&
		c.MySQLROPassword != "" &&
		c.MySQLROPort != "" &&
		c.MySQLROUser != "" {
		c.MySQLRODBConn = fmt.Sprintf(mySQLDBConnFormat,
			c.MySQLROUser,
			c.MySQLROPassword,
			c.MySQLROHost,
			c.MySQLROPort,
			c.MySQLRODatabase,
		)
	}
}

func parseAuthConfigs(svcCfg string, cfgFieldName string) ([]auth.ClientConfig, error) {
	var cfgs []auth.ClientConfig
	err := json.Unmarshal([]byte(svcCfg), &cfgs)
	if err != nil {
		return nil, ErrAuthConfig{cfgFieldName, err}
	}

	for _, cfg := range cfgs {
		err = cfg.Valid()
		if err != nil {
			return nil, ErrAuthConfig{cfgFieldName, err}
		}
	}
	return cfgs, nil
}

func buildHMACConfig(cfg *configStruct) (transport.ServerAuthConfig, error) {
	pkgReadCfg, err := parseAuthConfigs(cfg.PkgReadAuthConfig, "pkg-read-auth-config")
	if err != nil {
		return transport.ServerAuthConfig{}, err
	}

	legacyCfg, err := parseAuthConfigs(cfg.LegacyAuthConfig, "legacy-auth-config")
	if err != nil {
		return transport.ServerAuthConfig{}, err
	}

	pkgWriteCfg, err := parseAuthConfigs(cfg.PkgWriteAuthConfig, "pkg-write-auth-config")
	if err != nil {
		return transport.ServerAuthConfig{}, err
	}

	dotcomCfg, err := parseAuthConfigs(cfg.DotcomAuthConfig, "dotcom-auth-config")
	if err != nil {
		return transport.ServerAuthConfig{}, err
	}

	return transport.ServerAuthConfig{
		PkgWrite:  pkgWriteCfg,
		PkgRead:   pkgReadCfg,
		LegacyTMA: legacyCfg,
		Dotcom:    dotcomCfg,
	}, nil
}

// parse command line flags and environment variables
func initServerCommand(runFn func(*cobra.Command, []string) error) *cobra.Command {
	var cmdServer = &cobra.Command{
		Use:              "server",
		Short:            "Run the TMA server",
		Long:             "Run the Trust Metadata API server",
		PersistentPreRun: initConfig,
		RunE:             runFn,
	}

	cmdServer.Flags().StringP("api-port", "p", "8080", "API server port")
	cmdServer.Flags().StringP("app-env", "e", "production", "environment")
	cmdServer.Flags().StringP("azure-blob-account", "", "", "Azure Blob Account")
	cmdServer.Flags().StringP("azure-blob-container", "", "attestations", "Azure Blob container")
	cmdServer.Flags().String("backend", "mysql", "database backend: <mysql, memory>")
	cmdServer.Flags().StringP("config", "c", "", "provide a configuration file")
	cmdServer.Flags().String("dogstatsd-host", "", "dogstatsd host")
	cmdServer.Flags().StringSlice("kafka-brokers", []string{}, "Kafka brokers for Hydro")
	cmdServer.Flags().String("kafka-client-id", "", "Kafka client ID")
	cmdServer.Flags().String("kafka-root-ca", "", "Kafka root CA for SSL")
	cmdServer.Flags().String("legacy-auth-config", "", "TMA Legacy HMAC config")
	cmdServer.Flags().String("log-level", "info", "logging verbosity: <debug, info>")
	cmdServer.Flags().String("mysql-database", "", "MySQL database")
	cmdServer.Flags().String("mysql-host", "", "MySQL host address")
	cmdServer.Flags().String("mysql-password", "", "MySQL password")
	cmdServer.Flags().String("mysql-port", "", "MySQL host port")
	cmdServer.Flags().String("mysql-user", "", "MySQL user")
	cmdServer.Flags().String("mysql-ro-database", "", "MySQL ro database")
	cmdServer.Flags().String("mysql-ro-host", "", "MySQL ro host address")
	cmdServer.Flags().String("mysql-ro-password", "", "MySQL ro password")
	cmdServer.Flags().String("mysql-ro-port", "", "MySQL ro host port")
	cmdServer.Flags().String("mysql-ro-user", "", "MySQL ro user")
	cmdServer.Flags().String("pkg-read-auth-config", "", "Package Info Read HMAC config")
	cmdServer.Flags().String("pkg-write-auth-config", "", "Package Info Write HMAC config")
	cmdServer.Flags().String("dotcom-auth-config", "", "Dotcom HMAC config")
	cmdServer.Flags().String("trusted-keys", "", "Trusted keys for bundle verification")
	cmdServer.Flags().String("tuf-directory", "tufdata", "Directory to store TUF metadata")
	cmdServer.Flags().String("tuf-mirror", "https://tuf-repo.github.com", "URL from where to fetch TUF updates")
	cmdServer.Flags().String("stamp", "", "Name of the stamp to use")

	return cmdServer
}
