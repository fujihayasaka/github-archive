// Runs various transitions of the billing platform data.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/data"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/hydro"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"

	"github.com/github/billing-platform/internal/transitions"
)

var transitionType = flag.String("type", "", "a specific type of transition to run")
var dryRun = flag.Bool("dry_run", true, "whether to run the transition in dry run mode")
var customerID = flag.String("customer_id", "", "a customer to run the transition for")
var customerIDList = flag.String("customer_ids", "", "a comma delimited list of customers to run the transition for (e.g. 1,2,3,4)")
var useFile = flag.Bool("use_default_input_file", false, "use the default input file setup for the transition")
var partitionKey = flag.String("partition_key", "", "a partition key to run the transition for")
var limit = flag.Int("limit", 0, "a limit for the number of items to delete from the partition")
var rate = flag.Int("rate", 0, "a rate limit for the number of batches to process from the partition per second")
var verbose = flag.Bool("verbose", true, "whether to log verbose output")
var skipParentEnterprise = flag.Bool("skip_parent_enterprise", false, "whether to emitAzureUsage for the parent enterprise")
var skipCostCenters = flag.Bool("skip_cost_centers", false, "whether to emitAzureUsage for cost centers within the parent enterprise")

func main() {
	if err := realMain(); err != nil {
		fmt.Printf("level=error message=%q\n", err)
		os.Exit(1)
	}
}

func realMain() error {
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("Failed loading config: %v\n", err)
		return err
	}

	if err = cfg.ValidateBaseConfig(); err != nil {
		fmt.Printf("Failed validating config: %v\n", err)
		return err
	}

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		fmt.Printf("Failed configuring telemetry: %v\n", err)
		return errors.Wrap(err, "failed configuring telemetry")
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, "Transition")
	logger.Info("initializing service",
		kvp.Int("net.host.port", cfg.HTTPPort),
		kvp.String("db.cosmosdb.container", cfg.ContainerName),
		kvp.String("db.cosmosdb.database", cfg.DatabaseName),
		kvp.String("db.cosmosdb.host", cfg.DatabaseEndPoint),
		kvp.String("db.cosmosdb.gateway_host", cfg.GatewayDatabaseEndPoint),
	)

	logger.Info("Initializing transition job...", kvp.String("gh.billing_platform.transition.type", *transitionType), kvp.Bool("dryRun", *dryRun))

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "transition", "transition_type": *transitionType, "dry_run": fmt.Sprintf("%t", *dryRun)})
	statter.Run()
	defer statter.Stop()

	statter.Counter("billing.transition.run", stats.Tags{"billing.transition_type": *transitionType}, 1)

	flagger := cfg.NewFeatureFlagClient(logger, statter)

	client, err := messaging.NewMessagingClient(ctx, cfg, statter)
	if err != nil {
		return errors.Wrap(err, "failed to create messaging client")
	}

	tracer := telem.Tracer.Tracer

	hydroPublisher, err := hydro.NewHydroPublisher(ctx, cfg, logger)
	if err != nil {
		return errors.Wrap(err, "failed to create hydro publisher")
	}

	monolithClient, err := cfg.NewMonolithClient(ctx)
	if err != nil {
		return err
	}

	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)
	if readWriteDB == nil {
		return errors.New("failed to create database")
	}

	engineParams := engines.NewEngineParams(client, cfg, readWriteDB, flagger, statter, monolithClient, tracer)
	usageEngine := engines.NewUsageEngine(engineParams)
	customerEngine := engines.NewCustomerEngine(engineParams)
	costCenterEngine := engines.NewCostCenterEngine(engineParams)
	azureEmissionEngine := engines.NewAzureEmissionEngine(engineParams)
	pricingEngine := engines.NewPricingEngine(engineParams)
	dataService := data.NewDataService(hydroPublisher, usageEngine, costCenterEngine, logger, statter)
	ac := azurecommerce.NewAzureCommerceClient()

	customerIDs := []string{}
	if *customerID != "" {
		customerIDs = append(customerIDs, *customerID)
	} else if *customerIDList != "" {
		customerIDs = strings.Split(*customerIDList, ",")
	}

	switch *transitionType {
	case "line_items":
		return transitions.NewLineItemsBackfillTransition(ctx, cfg, logger, customerEngine, costCenterEngine, usageEngine, hydroPublisher).Run(*dryRun, *customerID)
	case "yearly_discount":
		return transitions.NewYearlyDiscountBackfillTransition(ctx, cfg, logger, customerEngine, costCenterEngine, usageEngine, readWriteDB).Run(*dryRun, *customerID)
	case "invoice":
		return transitions.NewInvoiceBackfillTransition(ctx, cfg, logger, ac, azureEmissionEngine, customerEngine, costCenterEngine, usageEngine, dataService).Run(*dryRun)
	case "delete_by_org_repo_product_sku":
		return transitions.NewDeleteByOrgRepoProductSKUTransition(ctx, cfg, logger, customerEngine, costCenterEngine, usageEngine, readWriteDB).Run(*dryRun, customerIDs)
	case "emit_azure_usage":
		return transitions.NewEmitAzureUsageTransition(cfg, logger, ac, pricingEngine, customerEngine, azureEmissionEngine, costCenterEngine, dataService, readWriteDB).Run(ctx, *dryRun, *skipParentEnterprise, *skipCostCenters)
	case "add_cost_center_state":
		return transitions.NewCostcenterStateFieldTransition(ctx, cfg, logger, costCenterEngine, customerEngine, readWriteDB).Run(*dryRun, customerIDs, *useFile)
	case "remove_by_target_cost_center_docs":
		return transitions.NewRemoveByTargetCostCenterDocs(ctx, cfg, logger, costCenterEngine, customerEngine, readWriteDB).Run(*dryRun, customerIDs, *useFile)
	case "delete_partition_data":
		return transitions.NewDeletePartitionDataTransition(ctx, cfg, logger, readWriteDB).Run(*dryRun, *partitionKey, *limit, *rate)
	case "backfill_daily_rollups":
		return transitions.NewBackfillDailyRollups(ctx, cfg, logger, costCenterEngine, customerEngine, usageEngine, readWriteDB).Run(*dryRun, customerIDs, *useFile)
	case "backfill_monthly_rollups":
		return transitions.NewBackfillMonthlyRollups(ctx, cfg, logger, costCenterEngine, customerEngine, usageEngine, readWriteDB).Run(*dryRun, customerIDs, *useFile)
	case "backfill_yearly_rollups":
		return transitions.NewBackfillYearlyRollups(ctx, cfg, logger, costCenterEngine, customerEngine, usageEngine, readWriteDB).Run(*dryRun, customerIDs, *useFile)
	case "sku_to_cosmos":
		return transitions.NewSkuToCosmosTransition(logger, readWriteDB).Run(ctx, *dryRun, *verbose)
	default:
		return nil
	}
}
