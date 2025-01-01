// Command parse-sarif ingests SARIF data into Turboscan.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/github/turboscan/ts/app"

	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/processor"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/golang/protobuf/ptypes/timestamp"

	"github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/google/uuid"

	"github.com/github/go-stats"

	"github.com/github/github-telemetry-go/log"
	"github.com/jinzhu/gorm"
	"google.golang.org/protobuf/proto"

	"github.com/pkg/errors"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/sarif/store"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/sarif"
)

type Args struct {
	repoID       uint64
	repoNWO      string
	ownerID      uint64
	commit       string
	ref          string
	analysisName string
	analysisKey  string
	checkoutURI  string
	protoOut     bool
	s3path       string
	savePath     string
	kafka        bool
	paths        []string
	env          string
	runID        uint64
	startTime    *time.Time
	trackStatus  bool
}

func parseArgs() (*Args, error) {
	var args Args
	// These flags define the metadata for the analysis
	flag.Uint64Var(&args.repoID, "repo", 0, "repository id to create alerts for")
	flag.StringVar(&args.repoNWO, "nwo", "", "repository nwo")
	flag.Uint64Var(&args.ownerID, "owner_id", 0, "owner ID")
	flag.StringVar(&args.commit, "commit", "", "commit sha to create alerts for")
	flag.StringVar(&args.ref, "ref", "refs/heads/main", "qualified ref name to create alerts for")
	flag.StringVar(&args.analysisName, "analysis-name", "analysis", "name for the analysis")
	flag.StringVar(&args.analysisKey, "analysis-key", "", "key for the analysis")
	flag.StringVar(&args.checkoutURI, "checkout-uri", "", "URI at which the code was checked out when it was analyzed")
	flag.StringVar(&args.env, "env", "", "Environment configuration")
	flag.Uint64Var(&args.runID, "run-id", 0, "Worflow run id")
	tmpStartTime := flag.String("start-time", "", "Start time")

	// These flags define the operation mode of the tool
	flag.BoolVar(&args.protoOut, "proto", false, "Generate a <filename>.pb file using the hydro protobuf")
	flag.StringVar(&args.s3path, "s3", "", "Use the given S3 file path")
	flag.StringVar(&args.savePath, "s3-save", "", "Saves a copy of the S3 file to the given path")
	flag.BoolVar(&args.kafka, "kafka", false, "Send the message to Kafka")
	flag.BoolVar(&args.trackStatus, "track-status", false, "Store tool status information for the analysis")

	flag.Parse()
	args.paths = flag.Args()
	if *tmpStartTime != "" {
		t, err := time.Parse("2006-01-02T15:04:05Z07:00", *tmpStartTime)
		if err != nil {
			return nil, err
		}
		args.startTime = &t
	}
	return &args, nil
}

func main() {
	if err := realMain(); err != nil {
		fmt.Fprintf(os.Stderr, "%+v\n", err)
		os.Exit(1)
	}
}

func realMain() error {
	args, err := parseArgs()
	if err != nil {
		return err
	}

	if args.repoID == 0 {
		return errors.New("specify a non-zero repository ID with the -repo argument")
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "parse-sarif", func(ctx context.Context) error {
		logger := appctx.Logger(ctx)

		statsClient := appctx.Stats(ctx)

		var cleanup app.Cleaner
		defer cleanup.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleanup.Append(closeDB)

		switch {
		case args.kafka:
			return sendToKafka(ctx, logger, statsClient, cfg, db, args)
		case args.protoOut:
			return genHydro(ctx, logger, statsClient, cfg, db, args)
		case args.s3path != "":
			return downloadAndStore(ctx, logger, statsClient, cfg, db, args)
		default:
			return parseAndStore(ctx, logger, statsClient, cfg, db, args)
		}
	})
}

func makeDelivery(uri string, args *Args) (*ts.Delivery, error) {
	analysis := makeAnalysis(uri, args)
	env := ts.AnalysisEnv{}
	if analysis.Environment != "" {
		err := env.Scan(analysis.Environment)
		if err != nil {
			return nil, errors.Wrap(err, "failed to parse environment")
		}
	}

	return &ts.Delivery{
		RepositoryID:       ts.RepositoryEID(analysis.RepositoryId),
		RepositoryNWO:      ts.ToRepositoryNWO(analysis.RepoNwo),
		OwnerID:            ts.OwnerEID(analysis.OwnerId),
		Environment:        env,
		SarifPath:          analysis.SarifUri,
		CommitOid:          ts.ToSha(analysis.CommitOid),
		Ref:                analysis.Ref,
		AnalysisName:       ts.ToAnalysisName(analysis.AnalysisName),
		AnalysisKey:        ts.ToAnalysisKey(analysis.AnalysisKey),
		CheckoutURI:        ts.ToCheckoutURI(analysis.CheckoutUri),
		SourceRepositoryID: ts.RepositoryEID(analysis.RepositoryId),
		WorkflowRunID:      ts.WorkflowRunEID(analysis.WorkflowRunId),
		TrackStatus:        analysis.TrackStatus,
	}, nil
}

// makeAnalysis returns a protobuf Analysis from the commandline args and the give uri
func makeAnalysis(uri string, args *Args) *tshydro.Analysis {
	var startTime *timestamp.Timestamp
	if args.startTime != nil {
		startTime = &timestamp.Timestamp{
			Seconds: args.startTime.Unix(),
		}
	}
	msg := &tshydro.Analysis{
		RepositoryId:       args.repoID,
		SourceRepositoryId: args.repoID,
		RepoNwo:            args.repoNWO,
		OwnerId:            args.ownerID,
		SarifUri:           uri,
		CommitOid:          args.commit,
		Ref:                []byte(args.ref),
		AnalysisName:       args.analysisName,
		AnalysisKey:        args.analysisKey,
		CheckoutUri:        args.checkoutURI,
		Environment:        args.env,
		WorkflowRunId:      args.runID,
		BuildStartAt:       startTime,
		TrackStatus:        args.trackStatus,
	}

	return msg
}

// hydroPostSetup returns a HydroPost service configured with the given SarifService
func processorSetup(logger log.Logger, cfg *config.Config, db *gorm.DB, sarifService store.SarifStore) (*processor.Processor, error) {
	statsClient := cfg.NewStatsClient("parse-sarif-processor")
	kc, err := cfg.NewKafkaConfig(logger, statsClient)
	if err != nil {
		return nil, err
	}

	limitSelector := limits.NewLimitSelector(cfg.Limits(), cfg.DisableSarifHardLimit)

	alertService, err := app.NewAlertService(db)
	if err != nil {
		return nil, err
	}
	timelineEventService := timeline.NewService(db)

	toolService := tool.NewService(db, limitSelector)
	configurationService := configuration.NewService(db)

	ruleService := rule.NewService(db)
	analysisService := analysis.NewService(db)
	analysisMessageService := analysismessage.NewService(db)
	deliveryService := delivery.NewService(db)
	repoService := repository.NewService(db)

	publisher, err := publishers.New(*kc, statsClient)
	if err != nil {
		return nil, err
	}

	managedAnalysisService := managedanalysis.NewService(db, publisher)
	repoApi, err := cfg.NewRepositoryAPI(logger, statsClient)
	if err != nil {
		return nil, err
	}

	rma, err := sarif.DefaultRuleMetadataAugmentor()
	if err != nil {
		return nil, err
	}
	jobs, err := aqueduct.NewClient(cfg, logger, statsClient, nil)
	if err != nil {
		return nil, err
	}

	archivalStore, err := archivalstore.NewArchivalStoreFromConfig(sarifService, cfg)
	if err != nil {
		return nil, err
	}

	p := processor.New(alertService, analysisService, deliveryService, analysisMessageService, sarifService, archivalStore, toolService, configurationService, ruleService, timelineEventService, repoService, repoApi, limitSelector, rma, managedAnalysisService, nil, jobs)

	return p, nil
}

// genHydro uploads the SARIF file and creates a protobuf message for processing
func genHydro(ctx context.Context, logger log.Logger, s stats.Client, cfg *config.Config, db *gorm.DB, args *Args) error {
	sarifStore := store.NewSarifStore(cfg.GetStorageEngine(), cfg)
	if err := sarifStore.Open(ctx); err != nil {
		return err
	}
	defer sarifStore.Close(ctx)

	for _, path := range args.paths {
		logger.Info(fmt.Sprintf("Parsing file %s", path))
		err := func(path string) error {
			f, err := os.Open(path)
			if err != nil {
				return errors.Wrapf(err, "reading SARIF file %s has failed", path)
			}
			defer f.Close()

			uri := "testing/" + uuid.NewString()
			err = sarifStore.Upload(ctx, f, uri)
			if err != nil {
				return errors.Wrapf(err, "uploading SARIF file %s has failed", path)
			}
			logger.Info(fmt.Sprintf("SARIF file %s uploaded", uri))

			msg := makeAnalysis(uri, args)

			// Write to path.pb
			buf, err := proto.Marshal(msg)
			if err != nil {
				return errors.Wrapf(err, "marshaling file %s has failed", path)
			}

			pathOut := fmt.Sprintf("%s.pb", path)
			err = os.WriteFile(pathOut, buf, 0644)
			if err != nil {
				return errors.Wrapf(err, "writing file %s.pb has failed", path)
			}

			return nil
		}(path)
		if err != nil {
			return err
		}
	}
	return nil
}

func downloadAndStore(ctx context.Context, logger log.Logger, s stats.Client, cfg *config.Config, db *gorm.DB, args *Args) (err error) {
	sarifStore := store.NewSarifStore(cfg.GetStorageEngine(), cfg)
	if err := sarifStore.Open(ctx); err != nil {
		return err
	}
	defer func() {
		innerErr := sarifStore.Close(ctx)
		if err == nil {
			err = innerErr
		}
	}()

	if args.savePath != "" {
		f, err := os.OpenFile(args.savePath, os.O_RDWR|os.O_CREATE, 0755)
		if err != nil {
			return err
		}
		defer func() {
			innerErr := f.Close()
			if err == nil {
				err = innerErr
			}
		}()

		err = sarifStore.DownloadToWriter(ctx, args.s3path, f)
		if err != nil {
			return err
		}
	}

	processor, err := processorSetup(logger, cfg, db, sarifStore)
	if err != nil {
		return err
	}

	d, err := makeDelivery(args.s3path, args)
	if err != nil {
		return err
	}
	_, err = processor.ProcessNewDelivery(ctx, d)
	if err != nil {
		return err
	}

	logger.Info("Completed processing delivery.")
	return nil
}

func parseAndStore(ctx context.Context, logger log.Logger, s stats.Client, cfg *config.Config, db *gorm.DB, args *Args) error {
	sarifStore := store.NewSarifStore(config.STORAGE_MEMORY, cfg)
	if err := sarifStore.Open(ctx); err != nil {
		return err
	}
	defer sarifStore.Close(ctx)

	processor, err := processorSetup(logger, cfg, db, sarifStore)
	if err != nil {
		return errors.Wrap(err, "could not create hydroPost service")
	}

	for _, path := range args.paths {
		logger.Info(fmt.Sprintf("Parsing file %s", path))
		f, err := os.Open(path)
		if err != nil {
			return errors.Wrapf(err, "reading SARIF file %s has failed", path)
		}

		uri := "testing/" + uuid.NewString()
		err = sarifStore.Upload(ctx, f, uri)
		if err != nil {
			return errors.Wrapf(err, "uploading SARIF file %s has failed", path)
		}
		logger.Info(fmt.Sprintf("SARIF file %s uploaded", uri))

		d, err := makeDelivery(uri, args)
		if err != nil {
			return err
		}

		ctx = appctx.WithRepositoryID(ctx, uint64(d.RepositoryID))
		_, err = processor.ProcessNewDelivery(ctx, d)
		if err != nil {
			return err
		}
	}
	return nil
}

func sendToKafka(ctx context.Context, logger log.Logger, s stats.Client, cfg *config.Config, db *gorm.DB, args *Args) error {
	sarifStore := store.NewSarifStore(cfg.GetStorageEngine(), cfg)
	if err := sarifStore.Open(ctx); err != nil {
		return err
	}
	defer sarifStore.Close(ctx)

	kc, err := cfg.NewKafkaConfig(logger, nil)
	if err != nil {
		return err
	}
	publisher, err := publishers.New(*kc, stats.NullStatter)
	if err != nil {
		return err
	}
	defer publisher.Close()

	for _, path := range args.paths {
		logger.Info(fmt.Sprintf("Parsing file %s", path))
		f, err := os.Open(path)
		if err != nil {
			return errors.Wrapf(err, "reading SARIF file %s has failed", path)
		}

		uri := "testing/" + uuid.NewString()
		err = sarifStore.Upload(ctx, f, uri)
		if err != nil {
			return errors.Wrapf(err, "uploading SARIF file %s has failed", path)
		}
		logger.Info(fmt.Sprintf("SARIF file %s uploaded", path))

		msg := makeAnalysis(path, args)
		err = publisher.NewAnalysis(ctx, msg)
		if err != nil {
			return errors.Wrapf(err, "sending SARIF file %s has failed", path)
		}
		logger.Info(fmt.Sprintf("%s sent to hydro", path))
	}
	return nil
}
