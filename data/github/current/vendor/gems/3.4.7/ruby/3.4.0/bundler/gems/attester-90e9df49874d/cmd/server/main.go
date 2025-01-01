// Package main is the main package
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/github/attester/pkg/o11y"

	"github.com/github/attester/pkg/clients"
	"github.com/github/attester/pkg/service"
	boo_service "github.com/github/attester/pkg/service/boo"
	release_service "github.com/github/attester/pkg/service/release"
	"github.com/github/attester/pkg/transport"

	"github.com/github/github-telemetry-go/log"
	"github.com/spf13/cobra"
	"golang.org/x/sync/errgroup"
)

var GitCommit = "unknown"
var config configStruct

func main() {
	rootCmd := &cobra.Command{Use: "attester"}
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	rootCmd.AddCommand(initServerCommand(runServer))

	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}

func runServer(_ *cobra.Command, _ []string) error {
	var (
		err    error
		logger log.Logger
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
	logger = logger.Named("attester")

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

	// setup go-prof stats collection
	setupGoProfStats(mainCtx, metricsClient, logger)

	// setup exception reporting
	exceptionReporter, err := setupExceptionsReporter(config.AppEnv)
	if err != nil {
		logger.Error(err.Error())
	} else {
		httpOpts = append(httpOpts, transport.WithExceptionReporter(exceptionReporter))
	}

	// setup tracing
	stopTracing, err := o11y.StartTracing(logger)
	if err != nil {
		return err
	}
	// close the tracer in order to ensure spans are sent
	defer stopTracing()

	hmacConfig, err := buildHMACConfig(&config)
	if err != nil {
		return err
	}

	httpOpts = append(httpOpts, transport.WithHMACConfig(hmacConfig))

	booService, err := boo_service.NewBoo(exceptionReporter)
	if err != nil {
		return err
	}

	releaseCert, err := loadCert(config.ReleaseCertificatePath)
	if err != nil {
		return err
	}

	var releaseAttester *clients.Attester
	switch {
	case config.ReleaseAzureKeyVaultRef != "":
		{
			releaseAttester, err = clients.NewAttester(config.ReleaseAzureKeyVaultRef, config.TSAURL, releaseCert)
			if err != nil {
				return err
			}
		}
	case config.ReleasePrivateKeyPath != "":
		{
			signingKey, err := loadPrivateKey(config.ReleasePrivateKeyPath)
			if err != nil {
				return err
			}

			releaseAttester, err = clients.NewInMemoryAttester(signingKey, releaseCert)
			if err != nil {
				return err
			}
		}
	default:
		return errors.New("either release-azure-keyvault-ref or release-private-key-path must be set")
	}

	releaseService, err := release_service.NewRelease(releaseAttester, exceptionReporter)
	if err != nil {
		return err
	}
	services := []service.Service{booService, releaseService}

	// Setup HTTP server
	httpServer, err := transport.NewHTTP(
		services,
		GitCommit,
		":"+config.APIPort,
		httpOpts...,
	)

	if err != nil {
		return err
	}

	// Setup release service

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
