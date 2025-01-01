// Package main is the main package for the resource daemon.
package main

import (
	"context"
	"fmt"
	"net/http"
	_ "net/http/pprof" //nolint:gosec // pprof is disabled by default and is only meant for local debugging
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/github/migrations-vnext/internal/pkg/resourceworker"
	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	root = &cobra.Command{
		Long:  "mvnworker",
		RunE:  run,
		Short: "mvnworker",
		Use:   "mvnworker",
	}
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("kafka-addr", "0.0.0.0:19092", "the ip:port that the daemon will listen on")
	viper.BindPFlag("kafka-addr", root.PersistentFlags().Lookup("kafka-addr")) // #nosec

	root.PersistentFlags().Int("import-max-inflight-requests", 2, "the maximum number of in-flight import API calls")
	viper.BindPFlag("import-max-inflight-requests", root.PersistentFlags().Lookup("import-max-inflight-requests")) // #nosec

	root.PersistentFlags().String("base-url", "", "the base url the import client should use")
	viper.BindPFlag("base-url", root.PersistentFlags().Lookup("base-url")) // #nosec

	root.PersistentFlags().Bool("dummy-importer", false, "if the dummy importer should be used")
	viper.BindPFlag("dummy-importer", root.PersistentFlags().Lookup("dummy-importer")) // #nosec

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

	root.PersistentFlags().String("pprof-addr", "localhost:6066", "the ip:port that the pprof server will listen on")
	viper.BindPFlag("pprof-addr", root.PersistentFlags().Lookup("pprof-addr")) // #nosec

	root.PersistentFlags().Bool("enable-pprof", false, "whether to enable the pprof server")
	viper.BindPFlag("enable-pprof", root.PersistentFlags().Lookup("enable-pprof")) // #nosec

	root.PersistentFlags().Int64("enterprise-id", 1, "enterprise ID to which we add the organizations to, default is 1 (github-inc), use 4 in Proxima mode")
	viper.BindPFlag("enterprise-id", root.PersistentFlags().Lookup("enterprise-id")) // #nosec
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
	logger := telemetryProvider.Logger.Named("mvnworker")

	statter := stats.NewClient(os.Stdout, time.Second, "mvnworker")
	statter.Run()
	defer statter.Stop()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	kafkaAddr := viper.GetString("kafka-addr")
	importMaxInFlight := viper.GetInt("import-max-inflight-requests")
	redisAddr := viper.GetString("redis-addr")
	baseURL := viper.GetString("base-url")
	azureContainer := viper.GetString("azure-container-name")
	azureAddr := viper.GetString("azure-url")
	azureAccountName := viper.GetString("azure-account-name")
	azureAccountKey := viper.GetString("azure-account-key")
	pprofAddr := viper.GetString("pprof-addr")
	enablePprof := viper.GetBool("enable-pprof")
	dummyImporter := viper.GetBool("dummy-importer")
	enterpriseID := viper.GetInt64("enterprise-id")

	// Start pprof server if not disabled
	if enablePprof {
		go func() {
			logger.Info("starting pprof server", kvp.String("addr", pprofAddr))
			//nolint:gosec // setting timeout is not an issue here as it is only used for local debugging
			if err := http.ListenAndServe(pprofAddr, nil); err != nil {
				logger.WithError(err).Error("failed to start pprof server")
			}
		}()
	}

	// Create redis client
	opts := &redis.Options{
		Addr:     redisAddr, // Redis server address
		Password: "",        // No password set
		DB:       0,         // Use default DB
	}

	// Create a new Redis client.
	c := redis.NewClient(opts)

	// Create Kafka consumer
	consumer := kafka.NewKafkaGoConsumer(kafkaAddr, kafka.ResourceTopic, "job-consumer", "", importMaxInFlight, logger)

	// Create Kafka producer for failed resources
	dlProducer, err := kafka.NewKafkaGoProducer(kafkaAddr, kafka.FailedTopic, "", logger)
	if err != nil {
		return fmt.Errorf("failed to create kafka producer for failed topic: %w", err)
	}

	// Create Store for object store
	absPayload, err := blobstore.NewStore(ctx, azureAddr, azureAccountName, azureAccountKey, azureContainer, logger)
	if err != nil {
		return fmt.Errorf("failed to create Store: %w", err)
	}

	// Create worker to load payloads
	kv, err := resource.NewKVRedis(c, logger, statter)
	if err != nil {
		return fmt.Errorf("failed to create redis kv: %w", err)
	}
	// Create dag to process eligible nodes
	redisDAG, err := dag.NewRedisDAG(c, logger)
	if err != nil {
		return fmt.Errorf("failed to create redis DAG: %w", err)
	}

	loaderOpts := []resource.Option{
		resource.WithDAG(redisDAG),
		resource.WithKV(kv),
		resource.WithEnterpriseID(enterpriseID),
		resource.WithLogger(logger),
		resource.WithStatter(statter),
		resource.WithIntermediateStore(absPayload),
	}
	if baseURL != "" && !dummyImporter {
		httpClient, err := twirpAuth.NewRequestHMACSigner("octoshifthmac", &http.Client{})
		if err != nil {
			return fmt.Errorf("unable to create hmac signer: %w", err)
		}
		loaderOpts = append(loaderOpts, resource.WithImportClient(client.NewImportClient(baseURL, httpClient)))
	}
	loader := resource.NewLoaderImpl(loaderOpts...)

	// Create worker
	workerOpts := []resourceworker.Option{
		resourceworker.WithConsumer(consumer),
		resourceworker.WithLoader(loader),
		resourceworker.WithDeadLetterProducer(dlProducer),
		resourceworker.WithObjectStore(absPayload),
		resourceworker.WithLogger(logger),
		resourceworker.WithStatter(statter),
	}
	worker, err := resourceworker.New(workerOpts...)
	if err != nil {
		return fmt.Errorf("failed to create worker: %w", err)
	}

	// Consume and load payloads in a goroutine
	errC := make(chan error, 1)

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := worker.Run(ctx); err != nil {
			errC <- err
		}
	}()

	// Create a channel to listen for interrupt or terminate signals from the OS.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Wait for a stop signal
	select {
	case <-stop:
		logger.Info("received stop signal, shutting down...")
	case err = <-errC:
		return fmt.Errorf("failed to run worker: %w", err)
	}

	cancel()
	logger.Info("waiting for loader to finish...")
	wg.Wait()
	logger.Info("worker exiting...")
	return nil
}
