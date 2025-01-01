// Package main is the main package for the resource daemon.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:  "mvndagworker",
		RunE:  run,
		Short: "mvndagworker",
		Use:   "mvndagworker",
	}
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("kafka-addr", "0.0.0.0:19092", "the ip:port that the daemon will listen on")
	viper.BindPFlag("kafka-addr", root.PersistentFlags().Lookup("kafka-addr")) // #nosec

	root.PersistentFlags().String("redis-addr", "0.0.0.0:6379", "the ip:port that the daemon will listen on")
	viper.BindPFlag("redis-addr", root.PersistentFlags().Lookup("redis-addr")) // #nosec

	root.PersistentFlags().String("azure-container-name", "default", "the container to use for azure blob store")
	viper.BindPFlag("azure-container-name", root.PersistentFlags().Lookup("azure-container-name")) // #nosec

	root.PersistentFlags().String("azure-account-name", "devstoreaccount1", "azure account name")
	viper.BindPFlag("azure-account-name", root.PersistentFlags().Lookup("azure-account-name")) // #nosec

	root.PersistentFlags().String("azure-account-key", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==", "azure account key")
	viper.BindPFlag("azure-account-key", root.PersistentFlags().Lookup("azure-account-key")) // #nosec

	root.PersistentFlags().String("azure-url", "0.0.0.0:10000", "address for azure blob store")
	viper.BindPFlag("azure-url", root.PersistentFlags().Lookup("azure-url")) // #nosec

	root.PersistentFlags().String("namespace", "enterprise:4", "the namespace to use")
	viper.BindPFlag("namespace", root.PersistentFlags().Lookup("namespace")) // #nosec

	root.PersistentFlags().Int("num-concurrent-nodes", 100, "number of concurrent eligible nodes to process")
	viper.BindPFlag("num-concurrent-nodes", root.PersistentFlags().Lookup("num-concurrent-nodes")) // #nosec
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
	logger := telemetryProvider.Logger.Named("mvndagworker")

	statter := stats.NewClient(os.Stdout, time.Second, "mvndagworker")
	statter.Run()
	defer statter.Stop()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	kafkaAddr := viper.GetString("kafka-addr")
	redisAddr := viper.GetString("redis-addr")
	azureAddr := viper.GetString("azure-url")
	azureAccountName := viper.GetString("azure-account-name")
	azureAccountKey := viper.GetString("azure-account-key")
	azureContainer := viper.GetString("azure-container-name")
	namespace := viper.GetString("namespace")
	concurrency := viper.GetInt("num-concurrent-nodes")

	// Create the DAG worker
	c := redis.NewClient(&redis.Options{Addr: redisAddr, DB: 0, Password: ""})
	d, err := dag.NewRedisDAG(c, logger)
	if err != nil {
		return fmt.Errorf("failed to create redis DAG: %w", err)
	}

	absPayload, err := blobstore.NewStore(ctx, azureAddr, azureAccountName, azureAccountKey, azureContainer, logger)
	if err != nil {
		return fmt.Errorf("failed to create Store: %w", err)
	}

	eventProducer, err := kafka.NewKafkaGoProducer(kafkaAddr, kafka.EventTopic, "", logger)
	if err != nil {
		return fmt.Errorf("failed to create kafka producer: %w", err)
	}

	resourceProducer, err := kafka.NewKafkaGoProducer(kafkaAddr, kafka.ResourceTopic, "", logger)
	if err != nil {
		return fmt.Errorf("failed to create kafka producer: %w", err)
	}

	worker := dag.NewWorker(concurrency, d, absPayload, eventProducer, resourceProducer, logger.WithFields(kvp.String("component", "dag-worker")))

	go func() {
		if err := worker.ProcessEligibleNodes(ctx, namespace); err != nil {
			logger.WithError(err).Error("failed to run worker")
			cancel()
		}
	}()

	// Create a channel to listen for interrupt or terminate signals from the OS.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Wait for a stop signal
	<-stop
	cancel()

	logger.Info("worker exiting...")
	return nil
}
