// Package main is the main package for the preseed tool.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:  "preseed",
		RunE:  run,
		Short: "preseed",
		Use:   "preseed",
	}
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("preseed-path", "", "path to file that contains preseed data")
	viper.BindPFlag("preseed-path", root.PersistentFlags().Lookup("preseed-path")) // #nosec
	root.PersistentFlags().String("redis-addr", "0.0.0.0:6379", "the ip:port that the daemon will listen on")
	viper.BindPFlag("redis-addr", root.PersistentFlags().Lookup("redis-addr")) // #nosec
	root.PersistentFlags().String("namespace", "default", "namespace to use in DAG storage")
	viper.BindPFlag("namespace", root.PersistentFlags().Lookup("namespace")) // #nosec
}

func main() {
	if err := root.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) error {
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}
	logger := telemetryProvider.Logger.Named("preseed")

	path := viper.GetString("preseed-path")
	if path == "" {
		logger.Error("preseed-path flag must be set")
		return errors.New("preseed-path flag must be set")
	}

	redisAddr := viper.GetString("redis-addr")
	namespace := viper.GetString("namespace")

	// Create redis client
	opts := &redis.Options{
		Addr:     redisAddr, // Redis server address
		Password: "",        // No password set
		DB:       0,         // Use default DB
	}

	// Create a new Redis client.
	c := redis.NewClient(opts)

	// Create KVRedis
	kv, err := resource.NewKVRedis(c, logger, stats.NullStatter)
	if err != nil {
		return fmt.Errorf("failed to create kv store: %w", err)
	}

	d, err := dag.NewRedisDAG(c, logger)
	if err != nil {
		return fmt.Errorf("failed to create dag: %w", err)
	}

	// Create preseeded data
	if err := preseed(namespace, path, kv, d, logger); err != nil {
		return fmt.Errorf("failed to preseed kv store: %w", err)
	}

	return nil
}

// preseed reads the file at the given path and preseeds the kv store with the data
func preseed(namespace, path string, kv *resource.KVRedis, d *dag.RedisDAG, logger log.Logger) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Read the file
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("failed to open file: %w", err)
	}
	defer func() { _ = f.Close() }()

	type record struct {
		Key         string `json:"key"`
		Int64Value  int64  `json:"value_int64"`
		NodeKind    string `json:"node_kind"`
		StringValue string `json:"value_string"`
	}
	var records []record
	if err := json.NewDecoder(f).Decode(&records); err != nil {
		return fmt.Errorf("failed to decode file: %w", err)
	}

	// Preseed the kv store
	for _, record := range records {
		logger.Info("preseed kv store", kvp.Any("record", record))
		if record.StringValue != "" {
			if err := kv.AddStringResource(ctx, namespace, record.Key, record.StringValue); err != nil {
				return fmt.Errorf("failed to preseed kv store: %w", err)
			}
		}
		if record.Int64Value > 0 {
			if err := kv.AddInt64Resource(ctx, namespace, record.Key, record.Int64Value); err != nil {
				return fmt.Errorf("failed to preseed kv store: %w", err)
			}
		}

		nodeKind := dag.ResourceNode
		if record.NodeKind != "" {
			nodeKind = dag.NodeKindFromString(record.NodeKind)
		}
		if err = d.MarkAsProcessed(ctx, namespace, []dag.Node{{ID: dag.ID(record.Key), Kind: nodeKind}}); err != nil {
			return fmt.Errorf("failed to mark as processed: %w", err)
		}
	}

	return nil
}
