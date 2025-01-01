package main

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/hydro"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/pkg/transport"

	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/sigstore/sigstore/pkg/signature"
	"golang.org/x/sync/errgroup"

	"github.com/github/github-telemetry-go/log"
	"github.com/spf13/cobra"
)

var GitCommit = "unknown"

var config configStruct

func main() {
	rootCmd := &cobra.Command{Use: "tma"}
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	rootCmd.AddCommand(initServerCommand(runServer))

	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}

// setup and start the server
func runServer(_ *cobra.Command, _ []string) error {
	var (
		err          error
		azBlobClient azureblob.Client
		db           storage.DatabaseEndpoints
		logger       log.Logger
		hydroClient  *hydro.Client
		store        storage.Store
	)

	httpOpts := make([]transport.HTTPServerOption, 0)

	if config.LogLevel == "debug" {
		logger, err = log.NewFromConfig(log.Config{
			Environment:        config.AppEnv,
			LogLevel:           log.DebugLevel.String(),
			LogConsoleEncoding: "logfmt",
		})
		if err != nil {
			return err
		}
	} else {
		logger, err = log.NewFromConfig(log.Config{
			Environment:        config.AppEnv,
			LogLevel:           log.InfoLevel.String(),
			LogConsoleEncoding: "logfmt",
		})
		if err != nil {
			return err
		}
	}
	logger = logger.Named("trust-metadata-api")

	httpOpts = append(httpOpts, transport.WithLogger(logger))

	// Setup main context and cancel function to handle shutdown
	mainCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	httpOpts = append(httpOpts, transport.WithContext(mainCtx))

	// setup metrics
	metricsClient, err := setupMetricsClient(config, logger)
	if err != nil {
		logger.Error(err.Error())
	} else {
		httpOpts = append(httpOpts, transport.WithMetrics(metricsClient))
	}
	defer metricsClient.Stop() // Ensure the StatsD client will stop running

	// setup database and Azure blob storage backend
	switch config.Backend {
	case "mysql":
		db.Primary, err = mysql.NewLiveDatabase(config.MySQLDBConn, logger, metricsClient)
		if err != nil {
			return err
		}

		if config.MySQLRODBConn == "" {
			logger.Info("No replica configured, fall back to primary")
			db.Replica = db.Primary
		} else {
			logger.Info("Using read replica")
			db.Replica, err = mysql.NewLiveDatabase(config.MySQLRODBConn, logger, metricsClient)
			if err != nil {
				return err
			}
		}

		// We use the local client for testing purposes when we want to connect
		// with the Azure blob storage emulator (Azurite) hosted in Docker
		if azureblob.UseLocalClient(config.AzureBlobAccount) {
			azBlobClient, err = azureblob.NewLocalClient(config.AzureBlobContainer)
			if err != nil {
				return err
			}

			// if we're using the local client, we need to create the container
			if err = azBlobClient.CreateContainer(mainCtx, "attestations"); err != nil {
				return err
			}
			defer azBlobClient.DeleteContainer(mainCtx, "attestations") //nolint:errcheck
		} else {
			azBlobClient, err = azureblob.NewRemoteClient(config.AzureBlobAccount, config.AzureBlobContainer, logger, metricsClient)
			if err != nil {
				return err
			}
		}

		store = storage.NewLiveStore(azBlobClient, &db)
	case "memory":
		store = storage.NewInMemoryStore()
	default:
		return errors.New("invalid backend specified: " + config.Backend)
	}
	defer db.Close()

	// setup go-prof stats collection
	setupGoProfStats(mainCtx, metricsClient, logger)

	// setup database stats collection
	setupDBStats(mainCtx, metricsClient, config, &db, logger)

	// setup exception reporting
	exceptionReporter, err := setupExceptionsReporter(config.AppEnv)
	if err != nil {
		logger.Error(err.Error())
	} else {
		httpOpts = append(httpOpts, transport.WithExceptionReporter(exceptionReporter))
	}

	hydroClient, err = setupHydro(config, logger, exceptionReporter)
	if err != nil {
		logger.Error(err.Error())
	} else {
		httpOpts = append(httpOpts, transport.WithHydroClient(hydroClient))
	}

	// setup tracing
	stopTracing, err := o11y.StartTracing(logger)
	if err != nil {
		return err
	}
	// close the tracer in order to ensure spans are sent
	defer stopTracing()

	verifier, err := loadVerifier(&config, logger)
	if err != nil {
		return err
	}

	service, err := service.NewTMA(store, GitCommit, verifier, exceptionReporter)
	if err != nil {
		return err
	}

	hmacConfig, err := buildHMACConfig(&config)
	if err != nil {
		return err
	}

	httpOpts = append(httpOpts, transport.WithHMACConfig(hmacConfig))

	// Setup HTTP server
	httpServer, err := transport.NewHTTP(
		service,
		":"+config.APIPort,
		httpOpts...,
	)

	if err != nil {
		return err
	}

	// Use errgroup to control the lifecycle of the HTTP server
	group, groupCtx := errgroup.WithContext(mainCtx)
	group.Go(func() error {
		return httpServer.ListenAndServe()
	})
	group.Go(func() error {
		// When the main context is cancelled, gracefully stop the HTTP server
		<-groupCtx.Done()

		if err := httpServer.Shutdown(); err != nil {
			logger.Error(err.Error())
		}
		if err := hydroClient.Close(); err != nil {
			logger.Error(err.Error())
		}
		return nil
	})

	// Block until the errgroup is done
	if err := group.Wait(); err != nil {
		if errors.Is(err, http.ErrServerClosed) {
			logger.Info("HTTP server closed")
		} else {
			logger.Error(err.Error())
			return err
		}
	}

	return nil
}

// setupExceptionsReporter configures a new exceptions reporter for uncaught exceptions (Sentry)
func setupExceptionsReporter(appEnv string) (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stdout)

	// go-exceptions/http expects the FAILBOT_HAYSTACK_URL to be set in production
	_, ok := os.LookupEnv("FAILBOT_HAYSTACK_URL")
	if ok {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
		log.Info("FAILBOT_HAYSTACK_URL is set, sending exceptions to failbot")
	} else {
		log.Error("FAILBOT_HAYSTACK_URL is not set, discarding exceptions")
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("trust-metadata-api"),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithValues(map[string]string{
			"deployed_to": appEnv,
			"release":     GitCommit,
		}),
	)
	if err != nil {
		return nil, err
	}

	return reporter, nil
}

// setupTrustedKeys returns the trusted keys for npm attestations by fetching
// them from the TUF repository. If the config contains trusted keys, they are
// parsed and returned instead.
func setupTrustedKeys(cfg *configStruct) (map[string]*root.ExpiringKey, error) {
	// If no keys are provided, fetch them from the TUF repository
	if len(cfg.TrustedKeysParsed) == 0 {
		return attestation.FetchNpmKeys(cfg.TUFDirectory)
	}
	keys := make(map[string]*root.ExpiringKey)
	for hint, key := range cfg.TrustedKeysParsed {
		ecdsaKey, ok := key.(*ecdsa.PublicKey)
		if !ok {
			return nil, fmt.Errorf("invalid key type: %T", key)
		}
		verifier, err := signature.LoadECDSAVerifier(ecdsaKey, crypto.SHA256)
		if err != nil {
			return nil, err
		}
		validStart := time.Date(2022, 12, 1, 0, 0, 0, 0, time.UTC)
		validEnd := time.Time{}
		keys[hint] = root.NewExpiringKey(verifier, validStart, validEnd)
	}
	return keys, nil
}

func setupHydro(config configStruct, logger log.Logger, exceptionReporter *exceptions.Reporter) (*hydro.Client, error) {
	// KafkaClientID from string with space to array string to
	hydroConfig := hydro.Config{
		KafkaBrokers:  config.KafkaBrokers,
		KafkaClientID: config.KafkaClientID,
		KafkaRootCA:   config.KafkaRootCA,
	}
	return hydro.NewHydroClient(hydroConfig, logger, exceptionReporter)
}

func loadVerifier(cfg *configStruct, log log.Logger) (*attestation.TMAVerifier, error) {
	// Stamp should only be set for proxima deployments, which does not
	// allow npm or public good integration.
	if cfg.Stamp != "" {
		return loadStampVerifier(cfg, log)
	}

	trustedRoot, err := attestation.FetchPublicGoodTrustedRoot(cfg.TUFDirectory)
	if err != nil {
		return nil, err
	}

	trustedKeys, err := setupTrustedKeys(cfg)
	if err != nil {
		return nil, err
	}
	npmTrustedMaterial := attestation.NewNpmTrustedMaterial(trustedRoot, trustedKeys)

	ghTrustedMaterial, err := attestation.FetchGHTrustedRoot(cfg.TUFDirectory, cfg.TUFMirror, "", log)
	if err != nil {
		return nil, err
	}

	return attestation.NewTMAVerifier(trustedRoot, npmTrustedMaterial, ghTrustedMaterial), nil
}

// As there are no public repos in Proxima, only the stamp's trusted
// root is recognized.
func loadStampVerifier(cfg *configStruct, log log.Logger) (*attestation.TMAVerifier, error) {
	tr := fmt.Sprintf("%s.trusted_root.json", cfg.Stamp)

	ghTrustedMaterial, err := attestation.FetchGHTrustedRoot(
		cfg.TUFDirectory,
		cfg.TUFMirror,
		tr,
		log)
	if err != nil {
		return nil, err
	}

	return attestation.NewTMAVerifier(nil, nil, ghTrustedMaterial), nil
}
