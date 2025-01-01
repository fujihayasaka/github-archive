// Command turobscan-garbage-collector removes old analyses data from the database
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/gc"

	"github.com/pkg/errors"

	"gocloud.dev/blob"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/github/turboscan/ts/transforms"
)

type cleanType string

const (
	sarif                cleanType = "sarif"
	analysisAssociations cleanType = "analysis_associations"
	incomplete           cleanType = "incomplete"
)

var cleanLookup = map[ts.CleaningType]cleanType{
	ts.CleaningTypeSARIF:                sarif,
	ts.CleaningTypeAnalysisAssociations: analysisAssociations,
	ts.CleaningTypeIncomplete:           incomplete,
}

type arguments struct {
	age         int
	limit       int
	typesToRun  []ts.CleaningType
	repoID      int
	interactive bool
}

func parseArgs() *arguments {
	defaults := []ts.CleaningType{ts.CleaningTypeSARIF, ts.CleaningTypeAnalysisAssociations, ts.CleaningTypeIncomplete}

	var args arguments
	flag.IntVar(&args.age, "age", 30, "How old in days an analysis has to be before it's considered for cleaning.")
	flag.IntVar(&args.limit, "limit", 10000, "The maximum number of analyses to clean.")
	flag.IntVar(&args.repoID, "repoID", 0, "Restrict cleaning to only analyses for the specified repo ID.")
	flag.BoolVar(&args.interactive, "interactive", true, "Require confirmation before deleting any data.")

	defaultStrings := transforms.Map(defaults, func(t ts.CleaningType) string {
		return string(cleanLookup[t])
	})
	cleanHelp := fmt.Sprintf("What to clean (%s, %s or %s). Default: {%s}",
		sarif, analysisAssociations, incomplete, strings.Join(defaultStrings, ","))
	flag.Func("type", cleanHelp, func(s string) error {
		ty, err := typeFromArg(cleanType(s))
		if err != nil {
			return err
		}
		for _, t := range args.typesToRun {
			if t == ty {
				return errors.New("duplicate cleaning type")
			}
		}
		args.typesToRun = append(args.typesToRun, ty)
		return nil
	})
	flag.Parse()

	if args.typesToRun == nil {
		args.typesToRun = defaults
	}

	return &args
}

func typeFromArg(tp cleanType) (ts.CleaningType, error) {
	switch tp {
	case sarif:
		return ts.CleaningTypeSARIF, nil
	case analysisAssociations:
		return ts.CleaningTypeAnalysisAssociations, nil
	case incomplete:
		return ts.CleaningTypeIncomplete, nil
	default:
		return 0, errors.New("unknown cleaning type")
	}
}

func logArgumentSummary(args *arguments) {
	var repoDesc string
	if args.repoID > 0 {
		repoDesc = fmt.Sprintf("repository with RepoID %d", args.repoID)
	} else {
		repoDesc = "ALL REPOSITORIES"
	}

	cTypes := transforms.Map(args.typesToRun, func(ttr ts.CleaningType) string {
		return string(cleanLookup[ttr])
	})

	typeDesc := strings.Join(cTypes, ", ")

	var action string
	if !args.interactive {
		action = "Cleaning"
	} else {
		action = "This command will clean"
	}

	msg := fmt.Sprintf(
		"%s [%s] from analyses more than %d days old from %s",
		action, typeDesc, args.age, repoDesc)

	if !args.interactive {
		log.Info(msg)
	} else {
		fmt.Println(msg)
	}
}

func cleaningTypesString(types []ts.CleaningType) string {
	typeStrings := transforms.Map(types, func(t ts.CleaningType) string {
		return string(cleanLookup[t])
	})
	return strings.Join(typeStrings, ", ")
}

func promptForConfirmation(clTypes []ts.CleaningType, analyses []ts.Analysis) (bool, error) {
	analysisCount := len(analyses)
	fmt.Printf("This will clean %s for %d analyses, resulting in permanent data deletion.\n",
		cleaningTypesString(clTypes), analysisCount)
	reader := bufio.NewReader(os.Stdin)

	analysisIDs := transforms.Map(analyses, func(a ts.Analysis) ts.AnalysisID {
		return a.ID
	})

	analysisCountStr := strconv.Itoa(analysisCount)
	// Keep asking until we get a recognized answer
	for {
		fmt.Println("Please enter the number of analyses to be cleaned in order to continue")
		fmt.Printf("[%s (continue) / Q (quit, default) / l (list analysis IDs)]: ", analysisCountStr)
		resp, err := reader.ReadString('\n')
		if err != nil {
			return false, err
		}

		respL := strings.ToLower(strings.TrimSpace(resp))
		switch respL {
		case analysisCountStr:
			return true, nil
		case "q", "quit", "":
			return false, nil
		case "l", "list":
			fmt.Printf("%v\n\n", analysisIDs)
		default:
			fmt.Printf("Unrecognized response\n\n")
		}
	}
}

func main() {
	if err := realMain(); err != nil {
		log.WithError(err).Error("Unexpected error")
		os.Exit(1)
	}
}

func realMain() error {
	args := parseArgs()
	logArgumentSummary(args)

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "turboscan-garbage-collector", func(ctx context.Context) error {
		logger := appctx.Logger(ctx)
		statsClient := appctx.Stats(ctx)

		start := time.Now()
		defer func() {
			statsClient.DistributionMs("scheduled_job", stats.Tags{"job": "garbage-collector"}, time.Since(start))
		}()

		throttler := cfg.NewFrenoThrottler()

		db, err := config.DBWithReplicaConnection(&config.DBOptions{Config: cfg}, logger, statsClient)
		if err != nil {
			return err
		}
		defer func() {
			err = config.CloseDBAndReplicas(db)
			if err != nil {
				logger.WithError(err).Error("failed to close primary or replica connection")
			}
		}()

		// NOTE: It is surprising that we are not using the SarifService here but relying on accesing the bucket directly.
		//       This does not check that the connection to the bucket is still alive. This is probably fine, as GC
		//       is run as part of a job, so a failing connection will be retried on the next run of the job.
		var bucket *blob.Bucket

		engine := cfg.GetStorageEngine()
		switch {
		case engine == config.STORAGE_AZURE:
			bucket, err = store.GetAzureBucket(ctx, cfg.AzureAccountName, cfg.AzureAccountKey, cfg.AzureContainer, cfg.AzureEndpoint)
			if err != nil {
				return err
			}
		case engine == config.STORAGE_S3:
			bucket, err = store.GetS3Bucket(cfg.AWSID, cfg.AWSSecret, cfg.AWSRegion, cfg.S3Bucket, cfg.S3Endpoint)
			if err != nil {
				return err
			}
		default:
			return nil
		}

		alertBatchSize := 10000
		gcService := gc.NewService(db, bucket, alertBatchSize)

		clTypes := args.typesToRun
		logger.Info("Starting garbage collection...", kvp.String("gh.turboscan.type", cleaningTypesString(clTypes)))
		statsClient.Counter("gc_run.started", stats.Tags{}, 1)
		startTime := time.Now()

		// waitloop until freno clears us to clean if we're deleting
		// alert data
		canWrite := false
		for !canWrite {
			canWrite, err = throttler.CanWrite(ctx)
			if err != nil {
				logger.WithError(err).Error("Error checking Freno")
				statsClient.Counter("gc_analyses.freno_error", stats.Tags{}, 1)
				time.Sleep(1 * time.Second)
			}
			if !canWrite {
				logger.Info("Waiting on Freno")
				statsClient.Counter("gc_analyses.throttled", stats.Tags{}, 1)
				time.Sleep(1 * time.Second)
			}
		}

		garbageCollectableAnalyses, err := gcService.FetchGarbageCollectableAnalyses(gormext.WithTryReplica(ctx, true), args.age, args.limit, args.repoID)
		if err != nil {
			statsClient.Counter("gc_run.failed", stats.Tags{}, 1)
			statsClient.DistributionMs("gc_run.time", stats.Tags{"success": "false"}, time.Since(startTime))
			return err
		}

		if len(garbageCollectableAnalyses) == 0 {
			logger.Info("Skipping, no matching cleanable analyses")
			statsClient.Counter("gc_run.no_cleanable_analyses", stats.Tags{}, 1)
			return nil
		}

		// Check for confirmation if running in interactive mode now that
		// we know which analyses are affected
		if args.interactive {
			confirm, err := promptForConfirmation(clTypes, garbageCollectableAnalyses)
			if err != nil {
				return err
			}

			if !confirm {
				fmt.Println("Exiting")
				return nil
			}
		}

		gcService.CleanAnalyses(ctx, clTypes, garbageCollectableAnalyses)
		statsClient.DistributionMs("gc_run.time", stats.Tags{"success": "true"}, time.Since(startTime))

		return nil
	})
}
