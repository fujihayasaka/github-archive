// Package main is the main package for the eventdlworker utility.
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	eventworker "github.com/github/migrations-vnext/internal/pkg/event-worker"
	"github.com/github/migrations-vnext/internal/pkg/events"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:  "eventdlworker",
		RunE:  run,
		Short: "eventdlworker",
		Use:   "The event deadletter worker for Enterprise Live Migrations (ELM)",
	}
)

func init() { //nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("base-url", "", "the base url the import client should use")
	viper.BindPFlag("base-url", root.PersistentFlags().Lookup("base-url")) // #nosec

	root.PersistentFlags().String("kafka-addr", "0.0.0.0:19092", "the ip:port that the daemon will listen on")
	viper.BindPFlag("kafka-addr", root.PersistentFlags().Lookup("kafka-addr")) // #nosec

	root.PersistentFlags().String("redis-addr", "0.0.0.0:6379", "the ip:port that the daemon will listen on")
	viper.BindPFlag("redis-addr", root.PersistentFlags().Lookup("redis-addr")) // #nosec
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
	logger := telemetryProvider.Logger.Named("event-deadletter-worker")

	statter := stats.NewClient(os.Stdout, time.Second, "event-deadletter-worker")
	statter.Run()
	defer statter.Stop()

	// Setup components
	baseURL := viper.GetString("base-url")
	kafkaAddr := viper.GetString("kafka-addr")
	redisAddr := viper.GetString("redis-addr")

	if baseURL == "" {
		return errors.New("baseURL is required")
	}
	httpClient, err := twirpAuth.NewRequestHMACSigner("octoshifthmac", &http.Client{})
	if err != nil {
		return fmt.Errorf("unable to create hmac signer: %w", err)
	}
	importClient := client.NewImportClient(baseURL, httpClient)

	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr, Password: "", DB: 0})
	redisDAG, err := dag.NewRedisDAG(redisClient, logger)
	if err != nil {
		return fmt.Errorf("failed to create redis DAG: %w", err)
	}

	consumer := kafka.NewKafkaGoConsumer(kafkaAddr, kafka.FailedEventTopic, "event-deadletter-worker-consumer", "", 1, logger)

	producer, err := kafka.NewKafkaGoProducer(kafkaAddr, kafka.FailedEventTopic, "", logger)
	if err != nil {
		return fmt.Errorf("failed to create kafka producer for failed topic: %w", err)
	}

	kv, err := resource.NewKVRedis(redisClient, logger, statter)
	if err != nil {
		return fmt.Errorf("failed to create redis kv: %w", err)
	}

	loader := events.New(importClient, kv, logger, statter)

	// Setup the worker
	var wg sync.WaitGroup
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errChan := make(chan error, 1)
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	logger.Info("starting event deadletter worker...")
	worker := eventworker.NewDeadLetterWorker(loader, consumer, producer, redisDAG, logger, statter)
	wg.Add(1)
	go func(ctx context.Context, errChan chan error, wg *sync.WaitGroup) {
		defer wg.Done()
		if err := worker.Run(ctx); err != nil {
			errChan <- err
		}
	}(ctx, errChan, &wg)

	// Wait for a stop signal
	select {
	case <-stopChan:
		logger.Info("received stop signal, shutting down...")
	case err = <-errChan:
		return fmt.Errorf("failed to run event deadletter worker: %w", err)
	}

	cancel()
	logger.Info("waiting for event deadletter worker to finish...")
	wg.Wait()
	logger.Info("event deadletter worker exiting...")

	return nil
}
