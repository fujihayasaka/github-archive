// Package main is the main package for the migrations-vnext daemon
// command-line.
package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/mvnd"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:              "the migrations-vnext daemon",
		PersistentPreRunE: validate,
		RunE:              run,
		Short:             "the migrations-vnext daemon",
		Use:               "mvnd",
	}
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("azure-account-key", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==", "Azure account key.")
	viper.BindPFlag("azure-account-key", root.PersistentFlags().Lookup("azure-account-key")) // #nosec

	root.PersistentFlags().String("azure-account-name", "devstoreaccount1", "Azure account name.")
	viper.BindPFlag("azure-account-name", root.PersistentFlags().Lookup("azure-account-name")) // #nosec

	root.PersistentFlags().String("azure-container-name", "default", "Azure blob storage container to use.")
	viper.BindPFlag("azure-container-name", root.PersistentFlags().Lookup("azure-container-name")) // #nosec

	root.PersistentFlags().String("azure-url", "0.0.0.0:10000", "Address for Azure Blob Store.")
	viper.BindPFlag("azure-url", root.PersistentFlags().Lookup("azure-url")) // #nosec

	root.PersistentFlags().String("dag-kind", "memory", "The DAG backend that will be used by mvnd.")
	viper.BindPFlag("dag-kind", root.PersistentFlags().Lookup("dag-kind")) // #nosec

	root.PersistentFlags().String("listen-addr", ":80", "The ip:port that the daemon will listen on.")
	viper.BindPFlag("listen-addr", root.PersistentFlags().Lookup("listen-addr")) // #nosec

	root.PersistentFlags().String("object-store-kind", "memory", "The Object Store backend that will be used by mvnd.")
	viper.BindPFlag("object-store-kind", root.PersistentFlags().Lookup("object-store-kind")) // #nosec

	root.PersistentFlags().String("redis-addr", "127.0.0.1:6379", "The ip:port of the Redis instance (for Redis DAG).")
	viper.BindPFlag("redis-addr", root.PersistentFlags().Lookup("redis-addr")) // #nosec

	root.PersistentFlags().String("twirp-hmac-keys", "", "Comma-separated list of HMAC keys for request verification")
	viper.BindPFlag("twirp-hmac-keys", root.PersistentFlags().Lookup("twirp-hmac-keys")) // #nosec
}

func main() {
	if err := root.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func createDag(cmd *cobra.Command, logger log.Logger) (dag.DAG, error) {
	kind := viper.GetString("dag-kind")
	switch kind {
	case "memory":
		return dag.NewMemoryDAG(), nil
	case "redis":
		redisAddr := viper.GetString("redis-addr")
		c := redis.NewClient(&redis.Options{Addr: redisAddr, Password: "", DB: 0})
		return dag.NewRedisDAG(c, logger)
	default:
		return nil, fmt.Errorf("unknown dag kind of %q requested", kind)
	}
}

func createObjectStore(cmd *cobra.Command, logger log.Logger) (dag.ObjectStore, error) {
	kind := viper.GetString("object-store-kind")
	switch kind {
	case "memory":
		return dag.NewMemoryObjectStore(), nil
	case "azure":
		azureAccountKey := viper.GetString("azure-account-key")
		azureAccountName := viper.GetString("azure-account-name")
		azureContainerName := viper.GetString("azure-container-name")
		azureURL := viper.GetString("azure-url")
		return blobstore.NewStore(context.Background(), azureURL, azureAccountName, azureAccountKey, azureContainerName, logger)
	default:
		return nil, fmt.Errorf("unknown object store kind of %q requested", kind)
	}
}

func createSASGenerator(cmd *cobra.Command, logger log.Logger) (blobstore.SASGenerator, error) {
	azureAccountKey := viper.GetString("azure-account-key")
	azureAccountName := viper.GetString("azure-account-name")
	azureContainerName := viper.GetString("azure-container-name")
	azureURL := viper.GetString("azure-url")
	return blobstore.NewStore(context.Background(), azureURL, azureAccountName, azureAccountKey, azureContainerName, logger)
}

func run(cmd *cobra.Command, _ []string) error {
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	logger := telemetryProvider.Logger.Named("mvnd")
	statter := stats.NewClient(os.Stdout, time.Second, "mvnd")
	statter.Run()
	defer statter.Stop()

	objectStoreI, err := createObjectStore(cmd, logger)
	if err != nil {
		return fmt.Errorf("error creating object store: %w", err)
	}

	dagI, err := createDag(cmd, logger)
	if err != nil {
		return fmt.Errorf("error creating dag instance: %w", err)
	}

	listenAddr := viper.GetString("listen-addr")
	hmacKeysStr := viper.GetString("twirp-hmac-keys")
	hmacKeys := splitHMACKeys(hmacKeysStr)

	sasGenerator, err := createSASGenerator(cmd, logger)
	if err != nil {
		return fmt.Errorf("error creating signed URL manager: %w", err)
	}

	daemon, err := mvnd.New(
		mvnd.WithListenAddr(listenAddr),
		mvnd.WithLogger(logger),
		mvnd.WithManager(dag.NewManager(dagI, objectStoreI, logger)),
		mvnd.WithStatter(statter),
		mvnd.WithHMACKeys(hmacKeys),
		mvnd.WithSASGenerator(sasGenerator),
	)
	if err != nil {
		logger.WithError(err).Error("failed to create instance of mvnd")
		return fmt.Errorf("failed to create instance of mvnd: %w", err)
	}

	logger.Info("starting mvnd", kvp.String("listen.addr", listenAddr))
	if err := daemon.Run(); err != nil {
		logger.WithError(err).Error("error returned from daemon")
		return fmt.Errorf("error returned from daemon: %w", err)
	}

	return nil
}

func splitHMACKeys(keys string) []string {
	if keys == "" {
		return nil
	}
	rawKeys := strings.Split(keys, ",")
	trimmedKeys := make([]string, 0, len(rawKeys))
	for _, key := range rawKeys {
		if k := strings.TrimSpace(key); k != "" {
			if _, err := hex.DecodeString(k); err != nil {
				continue
			}
			trimmedKeys = append(trimmedKeys, k)
		}
	}
	return trimmedKeys
}

func validate(cmd *cobra.Command, _ []string) error {
	// DAG Validations
	dagKind := viper.GetString("dag-kind")
	if dagKind != "memory" && dagKind != "redis" {
		return errors.New("invalid value for dag-kind flag, must be \"memory\" or \"redis\"")
	}

	if dagKind == "redis" {
		redisAddr := viper.GetString("redis-addr")
		if redisAddr == "" {
			return errors.New("redis-addr flag must be set when using redis dag")
		}
	}

	// ObjectStore validations
	objectStoreKind := viper.GetString("object-store-kind")
	if objectStoreKind != "memory" && objectStoreKind != "azure" {
		return errors.New("invalid value for object-store-kind flag, must be \"memory\" or \"azure\"")
	}

	if objectStoreKind == "azure" {
		azureAccountKey := viper.GetString("azure-account-key")
		if azureAccountKey == "" {
			return errors.New("azure-account-key flag must be set when using azure object store")
		}

		azureAccountName := viper.GetString("azure-account-name")
		if azureAccountName == "" {
			return errors.New("azure-account-name flag must be set when using azure object store")
		}

		azureContainerName := viper.GetString("azure-container-name")
		if azureContainerName == "" {
			return errors.New("azure-container-name flag must be set when using azure object store")
		}

		azureURL := viper.GetString("azure-url")
		if azureURL == "" {
			return errors.New("azure-url must be set when using azure object store")
		}
	}

	// HMAC validation
	hmacKeysStr := viper.GetString("twirp-hmac-keys")
	if hmacKeysStr == "" {
		return errors.New("twirp-hmac-keys flag must be set")
	}

	hmacKeys := splitHMACKeys(hmacKeysStr)
	if len(hmacKeys) == 0 {
		return errors.New("at least one valid HMAC key must be provided")
	}

	return nil
}
