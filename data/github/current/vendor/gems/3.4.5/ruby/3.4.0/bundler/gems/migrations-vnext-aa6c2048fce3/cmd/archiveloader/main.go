// Package main is the main package for the archive loader command-line.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/migrations-vnext/internal/pkg/adapters/archive"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:  "archiveloader",
		RunE:  run,
		Short: "archiveloader",
		Use:   "archiveloader",
	}
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("archive-root", "integration/fixtures/acme-widgets", "path to the root of the archive")
	viper.BindPFlag("archive-root", root.PersistentFlags().Lookup("archive-root")) // #nosec

	root.PersistentFlags().String("redis-addr", "0.0.0.0:6379", "address for Redis server")
	viper.BindPFlag("redis-addr", root.PersistentFlags().Lookup("redis-addr")) // #nosec

	root.PersistentFlags().String("container", "default", "container to use in KV store")
	viper.BindPFlag("container", root.PersistentFlags().Lookup("container")) // #nosec

	root.PersistentFlags().Int64("enterprise-id", 1, "enterprise ID to populate migration context with, default is 1 (github-inc), use 4 in Proxima mode")
	viper.BindPFlag("enterprise-id", root.PersistentFlags().Lookup("enterprise-id")) // #nosec

	root.PersistentFlags().String("azure-account-name", "devstoreaccount1", "azure account name")
	viper.BindPFlag("azure-account-name", root.PersistentFlags().Lookup("azure-account-name")) // #nosec

	root.PersistentFlags().String("azure-account-key", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==", "azure account key")
	viper.BindPFlag("azure-account-key", root.PersistentFlags().Lookup("azure-account-key")) // #nosec

	root.PersistentFlags().String("azure-url", "0.0.0.0:10000", "address for azure blob store")
	viper.BindPFlag("azure-url", root.PersistentFlags().Lookup("azure-url")) // #nosec

	root.PersistentFlags().String("allowed-orgs", "", "comma separated list of orgs to migrate from the archive, all if not set")
	viper.BindPFlag("allowed-orgs", root.PersistentFlags().Lookup("allowed-orgs")) // #nosec

	root.PersistentFlags().Bool("enable-shuffle", false, "whether resources should be shuffled before being loaded to simulate complete out-of-order ingestion")
	viper.BindPFlag("enable-shuffle", root.PersistentFlags().Lookup("enable-shuffle")) // #nosec

	root.PersistentFlags().StringSlice("allowed-resources", nil, "comma separated list of resources to load, all if not set, valid values are: "+validResourceTypes())
	viper.BindPFlag("allowed-resources", root.PersistentFlags().Lookup("allowed-resources")) // #nosec

	root.PersistentFlags().Int64("default-user-id", 2, "default user id is 2 (monalisa) use 25 for (monalisa_avo)")
	viper.BindPFlag("default-user-id", root.PersistentFlags().Lookup("default-user-id")) // #nosec
}

func main() {
	if err := root.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, _ []string) error {
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		panic(err)
	}
	logger := telemetryProvider.Logger.Named("archive-loader")

	rootArchive := viper.GetString("archive-root")
	orgs := viper.GetString("allowed-orgs")
	var allowedOrgs []string
	if orgs != "" {
		allowedOrgs = strings.Split(orgs, ",")
	}

	// Workaround for StringSlice arg vs. env compatibility.
	// https://github.com/spf13/viper/issues/380
	var allowedResources []string
	err = viper.UnmarshalKey("allowed-resources", &allowedResources)
	if err != nil {
		return fmt.Errorf("failed to unmarshal allowed-resources: %w", err)
	}
	allowedResourceTypes, err := toResourceTypes(allowedResources)
	if err != nil {
		return fmt.Errorf("failed to parse allowed-resources: %w", err)
	}

	redisAddr := viper.GetString("redis-addr")
	container := viper.GetString("container")
	enterpriseID := viper.GetInt64("enterprise-id")
	azureAddr := viper.GetString("azure-url")
	azureAccountName := viper.GetString("azure-account-name")
	azureAccountKey := viper.GetString("azure-account-key")
	shuffle := viper.GetBool("enable-shuffle")
	defaultUserID := viper.GetInt64("default-user-id")

	opts := &redis.Options{
		Addr:     redisAddr, // Redis server address
		Password: "",        // No password set
		DB:       0,         // Use default DB
	}

	// Create a new Redis client.
	c := redis.NewClient(opts)

	// Create a new Redis DAG.
	d, err := dag.NewRedisDAG(c, logger)
	if err != nil {
		return fmt.Errorf("failed to create redis DAG: %w", err)
	}

	// Create Store to store payloads
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	azureStore, err := blobstore.NewStore(ctx, azureAddr, azureAccountName, azureAccountKey, container, logger)
	if err != nil {
		return fmt.Errorf("failed to create Store: %w", err)
	}

	// Create a new archive loader.
	loader := archive.NewLoader(
		archive.WithRootPath(rootArchive),
		archive.WithAllowedResources(allowedResourceTypes),
		archive.WithShuffleResources(shuffle),
		archive.WithAllowedOrgs(allowedOrgs),
		archive.WithDefaultUserID(defaultUserID),
		archive.WithEnterpriseID(enterpriseID),
		archive.WithManager(dag.NewManager(d, azureStore, logger)),
		archive.WithSASGenerator(azureStore),
		archive.WithLogger(logger),
	)

	// Load archive to DAG
	if err = loader.ToDAG(); err != nil {
		return fmt.Errorf("error loading out of order: %w", err)
	}

	return nil
}

// validResourceTypes returns a comma separated list of valid resource types
func validResourceTypes() string {
	var res []string
	for i := 0; i != int(resource.TypeUnknown); i++ {
		res = append(res, resource.Type(i).String())
	}
	return strings.Join(res, ", ")
}

// toResourceTypes converts a slice of strings to a map of resource types
func toResourceTypes(resources []string) (map[resource.Type]struct{}, error) {
	var res []resource.Type
	for _, r := range resources {
		t := resource.ToType(r)
		if t == resource.TypeUnknown {
			return nil, errors.New("resource type is unknown: " + r)
		}
		res = append(res, t)
	}
	return resource.ToTypeSet(res...), nil
}
