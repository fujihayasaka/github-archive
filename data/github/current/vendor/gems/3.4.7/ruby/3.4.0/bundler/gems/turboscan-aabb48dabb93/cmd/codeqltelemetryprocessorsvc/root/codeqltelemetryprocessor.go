// Package root provides the service that powers codeqltelemetryprocessorsvc
package root

import (
	"context"
	"os"

	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

const (
	// Name for CodeQL's entry in the service catalog.
	codeqlServiceCatalogName = "codeql"
	// Name for the CodeQL application in Sentry.
	failbotAppName = "codeql"
	// Name for the CodeQL telemetry processor service.
	svcName          = "codeqltelemetryprocessorsvc"
	shortDescription = "consumes ProcessedAnalysis events from Hydro and processes CodeQL telemetry diagnostics contained within the SARIF files"
	longDescription  = "consumes ProcessedAnalysis events from Hydro and processes CodeQL telemetry diagnostics contained within the SARIF files."
)

var CodeQLTelemetryProcessorsCmd = &cobra.Command{
	Use:   svcName,
	Short: shortDescription,
	Long:  longDescription,
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	var cleanup app.Cleaner
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(publisher.Close)

	sarifStore, closeSarifStore, err := app.NewSarifStore(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeSarifStore)

	codeqlReporter, err := createCodeqlReporter(cfg)
	if err != nil {
		return nil, cleanup.Clean, errors.Wrap(err, "failed to create CodeQL error reporter")
	}

	p := consumers.NewCodeqlTelemetryProcessor(codeqlReporter, publisher, sarifStore, publisher)

	// We want to start consuming from the newest offset instead of the beginning of the topic
	consumer, err := consumers.NewConsumerServer(*kc, cfg.KafkaGroup, p, logger, consumers.ConsumeFromNewestOffset)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	return consumer, cleanup.Clean, nil
}

func createCodeqlReporter(cfg *config.Config) (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stderr)

	if cfg.IsProdEnv() {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
	}

	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication(failbotAppName),
		exceptions.WithValues(map[string]string{
			"deployed_to":                   cfg.FailbotDeployedTo,
			"release":                       cfg.FailbotRelease,
			"#kube_site":                    cfg.FailbotKubeSite,
			"#kube_cluster":                 cfg.FailbotKubeCluster,
			"#gh.exception.catalog_service": codeqlServiceCatalogName,
		}),
	)
	if err != nil {
		return nil, err
	}

	return reporter, nil
}
