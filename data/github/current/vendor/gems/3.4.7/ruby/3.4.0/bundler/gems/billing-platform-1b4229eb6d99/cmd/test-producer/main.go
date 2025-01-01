// nolint
package main

import (
	"context"
	"flag"
	"fmt"
	"math/rand"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/scheduler/jobs"
	"github.com/github/billing-platform/internal/transitions"
	"github.com/github/billing-platform/lib/api"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/services"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/pkg/errors"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/config" //nolint:staticcheck
	"google.golang.org/protobuf/types/known/timestamppb"

	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	protobuf "google.golang.org/protobuf/proto"
)

func main() {
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		panic(err)
	}

	logger := telem.Logger.WithLevel(log.InfoLevel)

	if err := produceMeteredUsage(logger, telem); err != nil {
		logger.WithError(err).Error("error running worker")
	}
}

func produceMeteredUsage(logger log.Logger, telem *telemetry.Provider) error {
	amountPtr := flag.Float64("amount", 100, "Amount of usage")
	// in dotcom, customer ID 1 points to GitHub-Inc
	customerIdPtr := flag.Int("customer_id", 1, "Customer ID")
	// in dotcom, organization ID 4 points to GitHub
	organizationIdPtr := flag.Int("organization_id", 5, "Organization ID")
	// in dotcom, repository ID 1 points to github org private-server repo
	repoIdPtr := flag.Int("repo_id", 1, "Repository ID")
	// in dotcom, user ID 2 points to monalisa
	actorIdPtr := flag.Int("actor_id", 2, "Actor ID")

	oneTimeUsageDatePtr := flag.String("one_time_usage_date", "", "Generate one-time usage on the specified date (YYYY-MM-DD)")
	daysSpanPtr := flag.Int("days_span", 0, "Generate historical usage spanning over the last specified number of days")
	hoursIntervalPtr := flag.Int("hours_interval", 1, "Generate usage every specified number of hours")
	skuPtr := flag.String("sku", "", "SKU")
	perCentagePtr := flag.Int("percentage", 0, "Discount Percentage of usage")
	runWatermarkJobPtr := flag.Bool("run_watermark_job", true, "Whether or not to run the watermark job after generating actions_storage or git_lfs_storage usage, defaults to true")
	planPtr := flag.String("plan_type", "enterprise", "Customer plan type to use, defaults to enterprise")

	ctx := context.Background()
	tracer := telem.Tracer.Tracer
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	statter := cfg.StatsClient()
	statter.Run()
	defer statter.Stop()

	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)
	flagger, err := featureflags.NewClient(ctx, cfg, logger, statter)
	if err != nil {
		logger.Error("failed to create feature flag client", kvp.String("error", err.Error()))
	}

	client, err := messaging.NewMessagingClient(ctx, cfg, statter)
	if err != nil {
		return nil
	}

	monolithClient, err := cfg.NewMonolithClient(ctx)
	if err != nil {
		return err
	}
	engineParams := engines.NewEngineParams(client, cfg, readWriteDB, flagger, statter, monolithClient, tracer)
	pricingEngine := engines.NewPricingEngine(engineParams)

	customerId := fmt.Sprintf("%d", int64(*customerIdPtr))
	customer := models.NewCustomerFrom(customerId, "", false, models.NoBillingTarget, "", "", "", *planPtr, false, 0, []string{"actions", "git_lfs", "copilot", "ghec", "ghas"}, true, false, false, false, &models.TradeScreening{}, models.CostCenterActive)
	created, err := readWriteDB.CreateIfNotExists(ctx, logger, customer)
	if err != nil {
		return err
	}

	if created {
		logger.Info("created new customer", kvp.String(logging.BillingCustomerId, customer.EnterpriseCustomerId))
	} else {
		logger.Info("using existing customer", kvp.String(logging.BillingCustomerId, customer.EnterpriseCustomerId))
	}

	// this will load all the skus + products into cosmosdb
	transitions.NewSkuToCosmosTransition(logger, readWriteDB).Run(ctx, false, false)

	client, err = messaging.NewMessagingClient(context.Background(), cfg, statter)
	if err != nil {
		return err
	}

	entityDetail := &hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(*customerIdPtr),
		OrganizationId: int64(*organizationIdPtr),
		RepoId:         int64(*repoIdPtr),
		ActorId:        int64(*actorIdPtr),
	}

	if *perCentagePtr > 0 {
		ctx := context.Background()
		telem, err := telemetry.NewFromEnv()
		if err != nil {
			return err
		}
		defer func() {
			if err := telem.Shutdown(ctx); err != nil {
				fmt.Printf("failed to shutdown telemetry: %v\n", err)
			}
		}()

		logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformWorker")
		logger.Info("initializing service",
			kvp.Int("net.host.port", cfg.HTTPPort),
			kvp.String("db.cosmosdb.container", cfg.ContainerName),
			kvp.String("db.cosmosdb.database", cfg.DatabaseName),
			kvp.String("db.cosmosdb.host", cfg.DatabaseEndPoint),
			kvp.String("db.cosmosdb.gateway_host", cfg.GatewayDatabaseEndPoint),
		)

		totalsPatching := engines.NewTotalPatchingEngine(engineParams)
		customerEngine := engines.NewCustomerEngine(engineParams)
		pricingEngine := engines.NewPricingEngine(engineParams)
		subscriptionsEngine := engines.NewSubscriptionsEngine(engineParams, totalsPatching, logger)
		discountEngine := engines.NewDiscountEngine(engineParams, pricingEngine, subscriptionsEngine)
		costCenterEngine := engines.NewCostCenterEngine(engineParams, pricingEngine, customerEngine)
		budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)
		discountService := services.NewDiscountService(discountEngine)
		budgetService := services.NewBudgetService(budgetEngine)
		costCenterService := services.NewCostCenterService(costCenterEngine)
		customerService := services.NewCustomerService(budgetService, customerEngine, discountService, costCenterService)

		customerApi := api.NewCustomerAPI(customerEngine, discountEngine, pricingEngine, costCenterEngine, budgetEngine, customerService, logger, statter, tracer, flagger)

		customerApi.CreateDiscount(ctx, &proto.CreateDiscountRequest{
			Discount: &proto.Discount{
				CustomerId: fmt.Sprint(entityDetail.CustomerId),
				Targets: []*proto.DiscountTarget{
					{
						Id:   fmt.Sprint(entityDetail.CustomerId),
						Type: proto.DiscountTargetType_EnterpriseDiscount,
					},
				},
				Percentage: 50,
				StartDate:  time.Date(2001, 5, 4, 3, 0, 0, 0, time.UTC).Unix(),
				EndDate:    time.Date(2031, 5, 4, 3, 0, 0, 0, time.UTC).Unix(),
			},
		})

		logger.Info("discount created")

		return nil
	}

	options := messaging.MessageSenderOptions()
	queueName := messaging.GetQueueNameDefault(models.WorkerTypeUsageIngestion)

	hours := 1
	hoursInterval := 1
	if *daysSpanPtr > 0 {
		hours = *daysSpanPtr * 24
		hoursInterval = *hoursIntervalPtr
	}

	currentTime := models.UTCNow()
	skipCache := false
	skus, err := pricingEngine.GetAllPricing(ctx, logger, skipCache)
	if err != nil {
		return errors.Wrap(err, "Unable to query pricings")
	}

	if *skuPtr != "" {
		// just do one sku
		sku := *skuPtr
		pricing, err := pricingEngine.GetPricing(ctx, logger, sku, false)
		if err != nil {
			return errors.Wrap(err, "Unable to query pricing sku")
		}

		skus = []*models.Pricing{pricing}
	}

	// Prepare the list of usage times
	var usageTimes []time.Time

	if *oneTimeUsageDatePtr != "" {
		// Parse the one-time usage date
		oneTimeUsageDate, err := time.Parse(time.DateOnly, *oneTimeUsageDatePtr)
		if err != nil {
			return errors.Wrap(err, "failed to parse one-time usage date")
		}
		usageTimes = append(usageTimes, oneTimeUsageDate)
	} else {
		// Generate recurring usage based on days_span and hours_interval
		for h := 0; h < hours; h += hoursInterval {
			usageTime := currentTime.Add(-time.Duration(h) * time.Hour).Time
			usageTimes = append(usageTimes, usageTime)
		}
	}

	// Generate usage messages for each SKU and usage time
	for _, sku := range skus {
		for _, t := range usageTimes {
			amount := *amountPtr
			if *daysSpanPtr > 0 {
				amount = *amountPtr * rand.Float64()
			}
			usageAt := timestamppb.New(t)
			message := createMessageForProductAndQuantity(sku.Sku, amount, entityDetail, usageAt)
			err = send(message, cfg, queueName, client, options, logger)
			if err != nil {
				return err
			}
		}
	}

	depth, err := client.QueueDepth(context.Background(), cfg.AqueductApplication(), queueName)
	if err != nil {
		panic(fmt.Errorf("error sending %w", err))
	}

	logger.Info("queue depth",
		kvp.String("aqueduct.app", cfg.AqueductApplication()),
		kvp.String("aqueduct.queue.name", queueName),
		kvp.Int64("aqueduct.queue.depth", depth),
	)

	// Run the watermark job when we've generated usage for a watermark product
	if *runWatermarkJobPtr {
		actionsStorageSkuPresent := findSku("actions_storage", skus)
		gitLfsStorageSkuPresent := findSku("git_lfs_storage", skus)
		packagesStorageSkuPresent := findSku("packages_storage", skus)
		if actionsStorageSkuPresent || gitLfsStorageSkuPresent || packagesStorageSkuPresent {
			for h := 0; h < hours; h += hoursInterval {
				// Allow time for usage to be processed before scheduling each watermark job
				logger.Info("Waiting before scheduling watermark jobs..")
				time.Sleep(5 * time.Second)
				t := currentTime.Add(-time.Duration(h) * time.Hour).Time
				jobRun := &models.WatermarkJobRun{
					CustomerId: customerId,
					Year:       int64(t.Year()),
					Month:      int64(t.Month()),
					Day:        int64(t.Day()),
					Hour:       int64(t.Hour()),
				}
				job := jobs.NewWatermarkDispatcherJob(ctx, cfg, logger, statter)
				job.Run(jobRun)
			}
		}
	}

	return nil
}

func send(
	message *hydroSchema.Usage,
	cfg *config.Config,
	queueName string,
	client aqueduct.Client,
	options []aqueduct.SendOption,
	logger log.Logger,
) error {
	messageBytes, err := protobuf.Marshal(message)
	if err != nil {
		return errors.Wrap(err, "failed to marshal message:")
	}

	envelope := schemas.Envelope{
		Message: messageBytes,
	}

	envelopeBytes, err := protobuf.Marshal(&envelope)
	if err != nil {
		errors.Wrap(err, "failed to marshal envelope:")
	}

	job := aqueduct.Job{
		App:     cfg.AqueductApplication(),
		Queue:   queueName,
		Payload: envelopeBytes,
	}
	_, err = client.Send(context.Background(), job, options...)
	if err != nil {
		logger.WithError(err).Error("error sending job",
			kvp.String("aqueduct.job.app", job.App),
			kvp.String("aqueduct.job.queue", job.Queue),
			kvp.String("aqueduct.job.payload", string(job.Payload)),
		)
	}
	return nil
}

func createMessageForProductAndQuantity(sku string, quantity float64, entityDetail *hydroSchemaEntities.EntityDetail, usageAt *timestamppb.Timestamp) *hydroSchema.Usage {
	return &hydroSchema.Usage{
		Sku:       sku,
		Quantity:  quantity,
		UsageAt:   usageAt,
		SourceUri: "git://run/id",
		Entity:    entityDetail,
	}
}

func findSku(sku string, allSkus []*models.Pricing) bool {
	for _, s := range allSkus {
		if s.Sku == sku {
			return true
		}
	}
	return false
}
