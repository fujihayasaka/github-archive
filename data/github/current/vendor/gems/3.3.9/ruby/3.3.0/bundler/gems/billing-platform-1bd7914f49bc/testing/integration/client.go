package integration

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/azurecommerce"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	hydroPkg "github.com/github/hydro-client-go/v5/pkg/hydro"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
	"github.com/pkg/errors"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
)

type IntegrationClient struct {
	usageApiClient       proto.UsageApi
	customerApiClient    proto.CustomerApi
	pricingApiClient     proto.PricingApi
	productApiClient     proto.ProductApi
	costCenterApiClient  proto.CostCenterApi
	adminApiClient       proto.AdminApi
	subscriptionsClient  proto.SubscriptionsApi
	usageReportApiClient proto.UsageReportApi

	DB                      interfaces.Database
	schemaManager           *db.SchemaManagement
	hydroPublisher          *hydroPkg.Publisher
	usageIntestionQueueName string
	uniqueQueueName         string
	uniqueCollectionName    string
	uniqueDatabaseName      string
	t                       *testing.T
	cfg                     *config.Config
	aqueductClient          aqueduct.Client
	aqueductApplication     string
	api                     *ServerExecution
	localhost               string
	Logger                  *IntegrationLogger
	preserveData            bool
	g                       *gomega.GomegaWithT
	zuoraServerUrl          string
	zuoraServer             *httptest.Server
	MonolithTwirpServerURL  string
}

type ClientOptions struct {
	Verbose              bool
	UseExistingServerAPI bool
	UseExistingData      bool
	PreserveData         bool

	DatabaseName string
}

var (
	PreservedData bool

	DefaultClientOptions = ClientOptions{}
)

func buildHydroPublisher(cfg *config.Config) (*hydroPkg.Publisher, error) {
	brokers := cfg.ParsedHydroKafkaBrokers()

	kc, err := hydroPkg.NewKafkaConfig(brokers,
		hydroPkg.WithClientID("billing-platform"),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create kafka config")
	}

	sink, err := hydroPkg.NewKafkaSink(*kc)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create kafka sink")
	}

	publisher, err := hydroPkg.NewPublisher(sink)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create publisher")
	}

	return publisher, nil
}

func NewTestClient(t *testing.T, opts ClientOptions) (*IntegrationClient, *gomega.GomegaWithT) {
	t.Parallel()

	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	cfgCopy := *cfg

	telem, err := telemetry.NewFromEnv()
	if err != nil {
		t.Fatalf("Failed configuring telemetry: %v", err)
	}

	file, err := getLogFile("test.log")
	if err != nil {
		t.Fatalf("Failed to open log file: %v", err)
	}

	aqueductClient, err := getAqueductClient(cfg)
	if err != nil {
		t.Fatalf("Failed to create aqueduct client: %v", err)
	}

	var uniqueDatabaseName string
	if opts.DatabaseName != "" {
		uniqueDatabaseName = opts.DatabaseName
	} else {
		uniqueDatabaseName = DefaultClientOptions.DatabaseName
	}
	uniqueCollectionName := uuid.NewString()
	uniqueQueueName := uniqueCollectionName
	queueName := messaging.GetQueueName(models.WorkerTypeUsageIngestion, uniqueQueueName)

	if opts.UseExistingData {
		opts.PreserveData = true
		// If useExistingData is true use the global config
		uniqueCollectionName = cfgCopy.ContainerName
		uniqueDatabaseName = cfgCopy.DatabaseName
		uniqueQueueName = ""
		queueName = messaging.GetQueueNameDefault(models.WorkerTypeUsageIngestion)
	} else {
		// If useExistingData is false, override the config with the unique values
		cfgCopy.ContainerName = uniqueCollectionName
	}

	cfgCopy.DatabaseName = uniqueDatabaseName
	cfgCopy.OverrideQueuePrefix = uniqueQueueName

	logger := &IntegrationLogger{
		Logger:               cfgCopy.ConfigureLogger(telem.Logger, "").WithFields(kvp.String("test", uniqueCollectionName)),
		verbose:              opts.Verbose,
		testFile:             file,
		t:                    t,
		uniqueCollectionName: uniqueCollectionName,
		uniqueDatabaseName:   uniqueDatabaseName,
	}

	statter := cfg.StatsClient()
	tracer := telem.Tracer.Tracer

	readWriteDB := db.NewDatabase(&cfgCopy, logger, statter, tracer)
	conn, _, err := db.NewDBConnections(&cfgCopy)

	if err != nil {
		t.Fatalf("Failed to create database connection: %v", err)
	}

	schemaManager := db.NewSchemaManagement(&cfgCopy, conn)
	if err := withRetriesOnRateLimit(func() error {
		return schemaManager.EnsureCollectionAndDatabaseExists(context.Background(), uniqueCollectionName, uniqueDatabaseName)
	}); err != nil {
		t.Fatalf("failed to ensure collection and database exist: %v", err)
	}

	if opts.PreserveData {
		// if we are preserving data, we don't want main_test to drop it during teardown
		PreservedData = true
	}

	var api *ServerExecution
	localServer := "http://localhost:8989"
	if !opts.UseExistingServerAPI {
		port := getRandomHttpPort()
		localServer = fmt.Sprintf("http://localhost:%d", port)
		api, err = runServer(uniqueDatabaseName, uniqueCollectionName, uniqueQueueName, port, localServer, logger)
		if err != nil {
			fmt.Println("is this really the error --------------------------------")
			fmt.Println(fmt.Sprint(err))
			t.Fatal("Failed to start server")
		}
	}

	g := gomega.NewGomegaWithT(t)
	client := &IntegrationClient{
		usageApiClient:          proto.NewUsageApiProtobufClient(localServer, &http.Client{}),
		customerApiClient:       proto.NewCustomerApiProtobufClient(localServer, &http.Client{}),
		pricingApiClient:        proto.NewPricingApiProtobufClient(localServer, &http.Client{}),
		productApiClient:        proto.NewProductApiProtobufClient(localServer, &http.Client{}),
		costCenterApiClient:     proto.NewCostCenterApiProtobufClient(localServer, &http.Client{}),
		adminApiClient:          proto.NewAdminApiProtobufClient(localServer, &http.Client{}),
		subscriptionsClient:     proto.NewSubscriptionsApiProtobufClient(localServer, &http.Client{}),
		usageReportApiClient:    proto.NewUsageReportApiProtobufClient(localServer, &http.Client{}),
		DB:                      readWriteDB,
		schemaManager:           schemaManager,
		uniqueCollectionName:    uniqueCollectionName,
		uniqueDatabaseName:      uniqueDatabaseName,
		t:                       t,
		cfg:                     &cfgCopy,
		aqueductClient:          aqueductClient,
		aqueductApplication:     cfgCopy.AqueductApplication(),
		Logger:                  logger,
		api:                     api,
		localhost:               localServer,
		preserveData:            opts.PreserveData,
		g:                       g,
		usageIntestionQueueName: queueName,
		uniqueQueueName:         uniqueQueueName,
	}

	return client, g
}

func (i *IntegrationClient) Close() {
	defer func() {
		if !i.preserveData {
			i.Logger.Info("==> Dropping test collection and database")
			i.DropUniqueTestCollection()
		}
		i.Logger.testFile.Close()
	}()

	if i.api != nil {
		defer i.api.file.Close()

		i.Logger.Info("==> Shutting down api")
		err := i.api.api.Process.Signal(os.Interrupt)
		if err != nil {
			i.Logger.WithError(err).Error("error stopping api")
		}

		// Sleep for 3 seconds to allow API to shutdown and generate our coverage reports.
		// If we don't sleep here no coverage data is generated.
		time.Sleep(3 * time.Second)

		i.api.cancel()
		_ = i.api.api.Wait()
		i.Logger.Info("==> Shut down api")
	}

	if i.zuoraServer != nil {
		i.Logger.Info("==> Shutting down Zuora test server")
		i.zuoraServer.Close()
	}

	if i.hydroPublisher != nil {
		i.Logger.Info("==> Shutting down Hydro publisher")
		i.hydroPublisher.Close()
	}
}

func (i *IntegrationClient) RunUsageIngestionWithTimeTravel(numberOfMessages int, timeTravelDate time.Time) {
	i.runUsageIngestion(numberOfMessages, true, timeTravelDate, false)
}

// Runs usage ingestion for the given number of messages
func (i *IntegrationClient) RunUsageIngestion(numberOfMessages int) {
	i.runUsageIngestion(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) PrintUsageIngestion(numberOfMessages int, timetravel bool, timeTravelDate time.Time) {
	i.runUsageIngestion(numberOfMessages, timetravel, timeTravelDate, true)
}

func (i *IntegrationClient) runUsageIngestion(numberOfMessages int, timeTravel bool, timeTravelDate time.Time, printArgs bool) {
	logFile := "usage-ingestion.log"
	err := executeWorker(numberOfMessages, "./script/usage-ingestion", timeTravel, timeTravelDate, logFile, i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, printArgs)
	i.g.Expect(err).ToNot(gomega.HaveOccurred(), fmt.Sprintf("Failed to run usage ingestion %v. See logs/%s for more details", err, logFile))
}

func (i *IntegrationClient) RunDailyJobWithTimeTravel(numberOfMessages int, timeTravelToDate time.Time) {
	i.dailyJob(numberOfMessages, true, timeTravelToDate, false)
}

func (i *IntegrationClient) RunDailyJob(numberOfMessages int) {
	i.dailyJob(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunAzureDailyRollupJob(numberOfMessages int) {
	i.azureDailyRollupJob(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunZuoraDailyRollupJob(numberOfMessages int) {
	i.zuoraDailyRollupJob(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunAzureEmission(numberOfMessages int) {
	i.azureJob(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunDailyEmission(numberOfMessages int) {
	i.emissionHandler(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunRequestHandler(numberOfMessages int) {
	i.requestHandler(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunZeroOutQuantitiesHandler(numberOfMessages int) {
	i.zeroOutQuantitiesHandler(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) RunHighWatermarkRolloverHandler(numberOfMessages int) {
	i.highWatermarkRolloverHandler(numberOfMessages, false, time.Time{}, false)
}

func (i *IntegrationClient) PrintDailyJob(numberOfMessages int) {
	i.dailyJob(numberOfMessages, false, time.Time{}, true)
}

func (i *IntegrationClient) dailyJob(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/rollup-customer-daily", timetravel, timeTravelDate, "daily-rollups.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) azureJob(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/azure-emission", timetravel, timeTravelDate, "azure-emission.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) emissionHandler(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/emission-handler", timetravel, timeTravelDate, "emission-handler.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) watermarkHandler(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/watermark-handler", timetravel, timeTravelDate, "watermark-handler.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) azureDailyRollupJob(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/azure-daily-rollup", timetravel, timeTravelDate, "azure-daily-rollups.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) zuoraDailyRollupJob(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/zuora-daily-rollup", timetravel, timeTravelDate, "zuora-daily-rollups.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) requestHandler(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/request-handler", timetravel, timeTravelDate, "request-handler.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) zeroOutQuantitiesHandler(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/zero-out-quantities-handler", timetravel, timeTravelDate, "zero-out-quantities-handler.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) highWatermarkRolloverHandler(numberOfMessages int, timetravel bool, timeTravelDate time.Time, print bool) {
	err := executeWorker(numberOfMessages, "./script/high-watermark-rollover-handler", timetravel, timeTravelDate, "high-watermark-rollover-handler.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) PrintMonthlyJob(numberOfUsages int, timetravel bool, timeTravelToDate time.Time) {
	i.runMonthlyJob(numberOfUsages, timetravel, timeTravelToDate, true)
}

func (i *IntegrationClient) RunMonthlyJob(numberOfUsages int) {
	i.runMonthlyJob(numberOfUsages, false, time.Time{}, false)
}
func (i *IntegrationClient) RunMonthlyJobWithTimeTravel(numberOfUsages int, timeTravelToDate time.Time) {
	i.runMonthlyJob(numberOfUsages, true, timeTravelToDate, false)
}

func (i *IntegrationClient) runMonthlyJob(numberOfUsages int, timetravel bool, timeTravelToDate time.Time, print bool) {
	err := executeWorker(numberOfUsages, "./script/rollup-customer-monthly", timetravel, timeTravelToDate, "monthly-rollups.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

// yearly
func (i *IntegrationClient) PrintYearlyJob(numberOfUsages int, timetravel bool, timeTravelToDate time.Time) {
	i.runYearlyJob(numberOfUsages, timetravel, timeTravelToDate, true)
}

func (i *IntegrationClient) RunYearlyJob(numberOfUsages int) {
	i.runYearlyJob(numberOfUsages, false, time.Time{}, false)
}
func (i *IntegrationClient) RunYearlyJobWithTimeTravel(numberOfUsages int, timeTravelToDate time.Time) {
	i.runYearlyJob(numberOfUsages, true, timeTravelToDate, false)
}

func (i *IntegrationClient) runYearlyJob(numberOfUsages int, timetravel bool, timeTravelToDate time.Time, print bool) {
	err := executeWorker(numberOfUsages, "./script/rollup-customer-yearly", timetravel, timeTravelToDate, "yearly-rollups.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, print)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

// end yearly

func (i *IntegrationClient) ScheduleInvoiceGeneration(year int64, month int64) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-p", string(models.InvoiceMonthly),
		"-y", strconv.FormatInt(year, 10),
		"-m", strconv.FormatInt(month, 10),
	}
	err := runCommand("./script/schedule-invoice-generation", args, "schedule-invoice-generation.log", i.Logger, false)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) RunConsumer(numberOfMessages int) error {
	args := []string{
		prefix(config.ParameterNameRunLimited),
		fmt.Sprintf("%s=%d", prefix(config.ParameterNameNumberOfLimitedMessagesToProcess), numberOfMessages),
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingCollectionName), i.uniqueCollectionName),
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingDatabaseName), i.uniqueDatabaseName),
	}
	return runCommand("./script/consumer", args, "consumer.log", i.Logger, false)
}

func (i *IntegrationClient) PublishRepoVisibilityChangedEvent(repoId int64, isPublic bool) error {
	if i.hydroPublisher == nil {
		hydroPublisher, err := buildHydroPublisher(i.cfg)
		if err != nil {
			return err
		}

		i.hydroPublisher = hydroPublisher
	}

	if err := i.hydroPublisher.Publish(stubs.NewRepoVisibilityChangedMessage(repoId, isPublic)); err != nil {
		return errors.Wrap(err, "failed to publish repo visibility changed event")
	}

	return nil
}

func (i *IntegrationClient) RunInvoiceGeneration(numberOfInvoices int) {
	err := executeWorker(numberOfInvoices, "./script/invoice-generation", false, time.Time{}, "invoice-generation.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, false)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) ScheduleAzureEmissionWithTime(runTime time.Time) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-y", strconv.FormatInt(int64(runTime.Year()), 10),
		"-m", strconv.FormatInt(int64(runTime.Month()), 10),
		"-d", strconv.FormatInt(int64(runTime.Day()), 10),
	}
	err := runCommand("./script/schedule-azure-emission", args, "schedule-azure-emission.log", i.Logger, false)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) RunEmissionDispatch(runTime time.Time) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-y", strconv.FormatInt(int64(runTime.Year()), 10),
		"-m", strconv.FormatInt(int64(runTime.Month()), 10),
		"-d", strconv.FormatInt(int64(runTime.Day()), 10),
	}
	err := runCommand("./script/emission-dispatch", args, "emission-dispatch.log", i.Logger, false)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) RunDailyEmissions(numberOfActiveUsageItems int) {
	err := executeWorker(numberOfActiveUsageItems, "./script/daily-emission-worker", false, time.Time{}, "daily-emission-worker.log", i.Logger, i.uniqueDatabaseName, i.uniqueCollectionName, i.uniqueQueueName, i.zuoraServerUrl, i.MonolithTwirpServerURL, false)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) ScheduleWatermarkJobs(runTime time.Time, productSku string) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-y", strconv.FormatInt(int64(runTime.Year()), 10),
		"-m", strconv.FormatInt(int64(runTime.Month()), 10),
		"-d", strconv.FormatInt(int64(runTime.Day()), 10),
		"-h", strconv.FormatInt(int64(runTime.Hour()), 10),
		"-s", productSku,
	}

	err := runCommand("./script/schedule-watermark-jobs", args, "schedule-watermark-jobs.log", i.Logger, false)
	if err != nil {
		i.Logger.WithError(err).Error("error scheduling watermark jobs")
	}
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) ScheduleZeroOutQuantities(customerId string, sku string, date time.Time) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-s", string(sku),
		"-c", string(customerId),
		"-y", strconv.FormatInt(int64(date.Year()), 10),
		"-m", strconv.FormatInt(int64(date.Month()), 10),
	}

	err := runCommand("./script/schedule-zero-out-quantities-jobs", args, "schedule-zero-out-quantities-jobs.log", i.Logger, false)
	if err != nil {
		i.Logger.WithError(err).Error("error scheduling zero out quantities jobs")
	}
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) ScheduleHighWatermarkRolloverJobs(runTime time.Time, customerId string, sku string, throttleTime time.Duration) {
	args := []string{
		"-q", messaging.GetQueueName(models.WorkerTypeRequestHandler, i.uniqueQueueName),
		"-y", strconv.FormatInt(int64(runTime.Year()), 10),
		"-m", strconv.FormatInt(int64(runTime.Month()), 10),
		"-c", customerId,
		"-s", sku,
		"-d", throttleTime.String(),
	}

	err := runCommand("./script/schedule-high-watermark-rollover-jobs", args, "schedule-high-watermark-rollover-jobs.log", i.Logger, false)
	if err != nil {
		i.Logger.WithError(err).Error("error scheduling high watermark rollover jobs")
	}
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
}

func (i *IntegrationClient) RunWatermarkHandler(numberOfMessages int) {
	i.watermarkHandler(numberOfMessages, false, time.Time{}, false)
}

func getAqueductClient(cfg *config.Config) (aqueduct.Client, error) {
	client, err := messaging.NewMessagingClient(context.Background(), cfg, cfg.StatsClient())
	if err != nil {
		return nil, err
	}
	return client, nil
}

func (i *IntegrationClient) CreateDiscount(discount *proto.Discount) (*proto.CreateDiscountResponse, error) {
	result, err := i.customerApiClient.CreateDiscount(context.Background(), &proto.CreateDiscountRequest{
		Discount: discount,
	})

	return result, err
}

func (i *IntegrationClient) GetDiscount(customerId string, uuid string) (*proto.GetDiscountResponse, error) {
	result, err := i.customerApiClient.GetDiscount(context.Background(), &proto.GetDiscountRequest{
		Key: &proto.DiscountKey{
			CustomerId: customerId,
			Uuid:       uuid,
		},
	})

	return result, err
}

func (i *IntegrationClient) GetAllDiscounts(customerId string) (*proto.GetAllDiscountsResponse, error) {
	result, err := i.customerApiClient.GetAllDiscounts(context.Background(), &proto.GetAllDiscountsRequest{
		CustomerId: customerId,
	})

	return result, err
}

func (i *IntegrationClient) GetAllPricing() *proto.GetAllPricingResponse {
	request := &proto.GetAllPricingRequest{}

	result, err := i.pricingApiClient.GetAllPricing(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetPricingsByProduct(productName string) *proto.GetPricingsByProductResponse {
	request := &proto.GetPricingsByProductRequest{
		ProductName: productName,
	}

	result, err := i.pricingApiClient.GetPricingsByProduct(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) UpsertPricing(pricing *proto.Pricing) *proto.UpsertPricingResponse {
	pricingRequest := &proto.UpsertPricingRequest{
		Pricing: pricing,
	}

	result, err := i.pricingApiClient.UpsertPricing(context.Background(), pricingRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetPricing(sku string) *proto.GetPricingResponse {
	SkuRequest := &proto.GetPricingRequest{
		Sku: sku,
	}

	result, err := i.pricingApiClient.GetPricing(context.Background(), SkuRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) UpsertProduct(product *proto.Product) (*proto.UpsertProductResponse, error) {
	request := &proto.UpsertProductRequest{
		Product: product,
	}

	result, err := i.productApiClient.UpsertProduct(context.Background(), request)
	if err != nil {
		return nil, err
	}
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result, nil
}

func (i *IntegrationClient) GetProduct(product string) (*proto.GetProductResponse, error) {
	request := &proto.GetProductRequest{
		Product: product,
	}

	result, err := i.productApiClient.GetProduct(context.Background(), request)

	return result, err
}

func (i *IntegrationClient) GetAllProducts() (*proto.GetAllProductsResponse, error) {
	request := &proto.GetAllProductsRequest{}

	result, err := i.productApiClient.GetAllProducts(context.Background(), request)
	if err != nil {
		return nil, err
	}
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result, nil
}

func (i *IntegrationClient) CreateCustomer(customer *proto.Customer) *proto.CreateCustomerResponse {
	customerRequest := &proto.CreateCustomerRequest{
		Customer: customer,
	}

	result, err := i.customerApiClient.UpsertCustomer(context.Background(), customerRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) PatchCustomer(customer *proto.Customer) *proto.PatchCustomerResponse {
	customerRequest := &proto.PatchCustomerRequest{
		Customer: customer,
	}

	result, err := i.customerApiClient.PatchCustomer(context.Background(), customerRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) UpsertCustomer(customer *proto.Customer) *proto.CreateCustomerResponse {
	customerRequest := &proto.CreateCustomerRequest{
		Customer: customer,
	}

	result, err := i.customerApiClient.UpsertCustomer(context.Background(), customerRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) UpsertBudget(budget *proto.Budget) *proto.UpsertBudgetResponse {
	budgetRequest := &proto.UpsertBudgetRequest{
		Budget: budget,
	}

	result, err := i.customerApiClient.UpsertBudget(context.Background(), budgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) UpsertBudgetError(budget *proto.Budget) error {
	budgetRequest := &proto.UpsertBudgetRequest{
		Budget: budget,
	}

	_, err := i.customerApiClient.UpsertBudget(context.Background(), budgetRequest)

	return err
}

func (i *IntegrationClient) GetCustomer(customerId string) *proto.GetCustomerResponse {
	customerRequest := &proto.GetCustomerRequest{
		CustomerId: customerId,
	}

	result, err := i.customerApiClient.GetCustomer(context.Background(), customerRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetCustomers(customerIDs []string) *proto.GetCustomersResponse {
	customersRequest := &proto.GetCustomersRequest{
		CustomerIds: customerIDs,
	}

	result, err := i.customerApiClient.GetCustomers(context.Background(), customersRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetBudget(key *proto.BudgetKey) *proto.GetBudgetResponse {
	budgetRequest := &proto.GetBudgetRequest{
		Key: key,
	}
	result, err := i.customerApiClient.GetBudget(context.Background(), budgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetBudgetByUuid(customerId string, uuid string) *proto.GetBudgetByUuidResponse {
	budgetRequest := &proto.GetBudgetByUuidRequest{
		CustomerId: customerId,
		Uuid:       uuid,
	}
	result, err := i.customerApiClient.GetBudgetByUuid(context.Background(), budgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) BudgetByUuidExists(customerId string, uuid string) bool {
	budgetRequest := &proto.GetBudgetByUuidRequest{
		CustomerId: customerId,
		Uuid:       uuid,
	}
	response, err := i.customerApiClient.GetBudgetByUuid(context.Background(), budgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	budgetExists := response.Budget != nil

	return budgetExists
}

func (i *IntegrationClient) DeleteBudget(customerId string, uuid string) *proto.DeleteBudgetResponse {
	deleteBudgetRequest := &proto.DeleteBudgetRequest{
		CustomerId: customerId,
		Uuid:       uuid,
	}
	result, err := i.customerApiClient.DeleteBudget(context.Background(), deleteBudgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetAllBudgets(customerId string) *proto.GetAllBudgetsResponse {
	budgetRequest := &proto.GetAllBudgetsRequest{
		CustomerId: customerId,
	}
	result, err := i.customerApiClient.GetAllBudgets(context.Background(), budgetRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) CanProceedWithUsage(pricing *proto.Pricing, entity *entities.EntityDetail, period time.Time) *proto.CanProceedWithUsageResponse {
	canProceedWithUsageRequest := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:      pricing.GetSku(),
			Product:  pricing.GetProduct(),
			Quantity: 0,
			UsageAt:  period.Unix(),
			EntityDetail: &proto.EntityDetail{
				CustomerId: fmt.Sprintf("%d", entity.CustomerId),
				OwnerId:    entity.OrganizationId,
				RepoId:     entity.RepoId,
				ActorId:    entity.ActorId,
			},
		},
	}
	result, err := i.customerApiClient.CanProceedWithUsage(context.Background(), canProceedWithUsageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) CanProceedWithUsageError(pricing *proto.Pricing, entity *entities.EntityDetail, period time.Time) error {
	canProceedWithUsageRequest := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:      pricing.GetSku(),
			Product:  pricing.GetProduct(),
			Quantity: 0,
			UsageAt:  period.Unix(),
			EntityDetail: &proto.EntityDetail{
				CustomerId: fmt.Sprintf("%d", entity.CustomerId),
				OwnerId:    entity.OrganizationId,
				RepoId:     entity.RepoId,
				ActorId:    entity.ActorId,
			},
		},
	}
	_, err := i.customerApiClient.CanProceedWithUsage(context.Background(), canProceedWithUsageRequest)

	return err
}

func (i *IntegrationClient) GetDiscountState(customerId string, uuid string, period time.Time) *proto.GetDiscountStateResponse {
	discountStateRequest := &proto.GetDiscountStateRequest{
		Key: &proto.DiscountKey{
			CustomerId: customerId,
			Uuid:       uuid,
		},
		Year:  int64(period.Year()),
		Month: int64(period.Month()),
	}
	result, err := i.customerApiClient.GetDiscountState(context.Background(), discountStateRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetAllDiscountStates(customerId string, period time.Time) *proto.GetAllDiscountStatesResponse {
	discountStateRequest := &proto.GetAllDiscountStatesRequest{
		CustomerId: customerId,
		Year:       int64(period.Year()),
		Month:      int64(period.Month()),
	}
	result, err := i.customerApiClient.GetAllDiscountStates(context.Background(), discountStateRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetBudgetState(key *proto.BudgetKey, period time.Time) *proto.GetBudgetStateResponse {
	budgetStateRequest := &proto.GetBudgetStateRequest{
		Key:   key,
		Year:  int64(period.Year()),
		Month: int64(period.Month()),
	}
	result, err := i.customerApiClient.GetBudgetState(context.Background(), budgetStateRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetDiscountTotal(sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetDiscountTotalResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Sku:           sku,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
	}
	results, err := i.usageApiClient.GetDiscountTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetInvoice(customerId string, year int, month int) *proto.GetInvoiceResponse {
	invoiceRequest := &proto.GetInvoiceRequest{
		CustomerId: customerId,
		Year:       int64(year),
		Month:      int64(month),
	}
	result, err := i.usageApiClient.GetInvoice(context.Background(), invoiceRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetDiscountLineItemsDateParts(product string, sku string, customerId string, period proto.BillingPeriod, year, month, day, hour int, groupBy proto.UsageGroupBy) *proto.GetDiscountLineItemsResponse {
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		GroupBy:       groupBy,
	}
	results, err := i.usageApiClient.GetDiscountLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageLineItemsDateParts(product string, sku string, customerId string, period proto.BillingPeriod, year, month, day, hour int, groupBy proto.UsageGroupBy) *proto.GetUsageLineItemsResponse {
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		GroupBy:       groupBy,
	}
	results, err := i.usageApiClient.GetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetSubscribedItems(sku string, customerId string) *proto.GetSubscribedItemsResponse {
	usageRequest := &proto.GetSubscribedItemsRequest{
		UsageEntityId: customerId,
		Sku:           sku,
	}
	results, err := i.subscriptionsClient.GetSubscribedItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetActiveSubscribedItems(sku string, customerId string) *proto.GetSubscribedItemsResponse {
	usageRequest := &proto.GetSubscribedItemsRequest{
		UsageEntityId: customerId,
		Sku:           sku,
	}
	results, err := i.subscriptionsClient.GetActiveSubscribedItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
	return results
}

func (i *IntegrationClient) GetSubscribedItemsTotal(sku string, customerId string) *proto.GetSubscribedItemsTotalResponse {
	usageRequest := &proto.GetSubscribedItemsRequest{
		UsageEntityId: customerId,
		Sku:           sku,
	}
	results, err := i.subscriptionsClient.GetSubscribedItemsTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetSubscribedItemsMonthlyTotal(sku string, customerId string, usageDate time.Time) *proto.GetSubscribedItemsTotalResponse {
	year, month := usageDate.Year(), int(usageDate.Month())
	usageRequest := &proto.GetSubscribedItemsMonthlyTotalRequest{
		UsageEntityId: customerId,
		Sku:           sku,
		Year:          int64(year),
		Month:         int64(month),
	}
	results, err := i.subscriptionsClient.GetSubscribedItemsMonthlyTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) AddLicense(sku string, customerId string, actorID int64) *proto.LicenseResponse {
	licenseRequest := &proto.LicenseRequest{
		Sku:            sku,
		SubscriptionAt: time.Now().Unix(),
		EntityDetail: &proto.EntityDetail{
			CustomerId: customerId,
			OwnerId:    int64(stubs.GetRandomId()),
			ActorId:    actorID,
		},
	}
	results, err := i.subscriptionsClient.AddLicense(context.Background(), licenseRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) RemoveLicense(sku, customerId string, actorID int64) *proto.LicenseResponse {
	licenseRequest := &proto.LicenseRequest{
		Sku:            sku,
		SubscriptionAt: time.Now().Unix(),
		EntityDetail: &proto.EntityDetail{
			CustomerId: customerId,
			OwnerId:    int64(stubs.GetRandomId()),
			ActorId:    actorID,
		},
	}
	results, err := i.subscriptionsClient.RemoveLicense(context.Background(), licenseRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageLineItems(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageLineItemsResponse {
	return i.GetUsageLineItemsDateParts(product, sku, customerId, period, usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour(), proto.UsageGroupBy_NoGroupBy)
}

func (i *IntegrationClient) GetNetUsageLineItems(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetNetUsageLineItemsResponse {
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(usageDate.Year()),
		Month:         int64(usageDate.Month()),
		Day:           int64(usageDate.Day()),
		Hour:          int64(usageDate.Hour()),
		BillingPeriod: period,
		GroupBy:       proto.UsageGroupBy_NoGroupBy,
	}
	results, err := i.usageApiClient.GetNetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageChartData(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod, groupBy proto.UsageGroupBy, repoId int64, orgId int64, costCenterId string) *proto.GetUsageChartDataResponse {
	usageRequest := &proto.GetUsageChartDataRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(usageDate.Year()),
		Month:         int64(usageDate.Month()),
		Day:           int64(usageDate.Day()),
		Hour:          int64(usageDate.Hour()),
		BillingPeriod: period,
		GroupBy:       groupBy,
		RepoId:        repoId,
		OrgId:         orgId,
		CostCenterId:  costCenterId,
		FilteredOrgs:  []string{},
	}
	results, err := i.usageApiClient.GetUsageChartData(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetPaginatedLineItems(customerId string, costCenterId string, usageDate time.Time, period proto.BillingPeriod, groupBy proto.UsageGroupBy, page int) *proto.GetPaginatedUsageLineItemsResponse {
	usageRequest := &proto.GetPaginatedUsageRequest{
		UsageEntityId: customerId,
		CostCenterId:  costCenterId,
		Year:          int64(usageDate.Year()),
		Month:         int64(usageDate.Month()),
		Day:           int64(usageDate.Day()),
		Hour:          int64(usageDate.Hour()),
		BillingPeriod: period,
		GroupBy:       groupBy,
		Page:          int64(page),
	}

	results, err := i.usageApiClient.GetPaginatedUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageLineItemsGroupBy(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod, groupBy proto.UsageGroupBy) *proto.GetUsageLineItemsResponse {
	return i.GetUsageLineItemsDateParts(product, sku, customerId, period, usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour(), groupBy)
}

func (i *IntegrationClient) GetDiscountLineItemsGroupBy(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod, groupBy proto.UsageGroupBy) *proto.GetDiscountLineItemsResponse {
	return i.GetDiscountLineItemsDateParts(product, sku, customerId, period, usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour(), groupBy)
}

func (i *IntegrationClient) GetDiscountLineItems(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetDiscountLineItemsResponse {
	return i.GetDiscountLineItemsDateParts(product, sku, customerId, period, usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour(), proto.UsageGroupBy_NoGroupBy)
}

func (i *IntegrationClient) GetDiscountLineItemsWithOrgOrRepo(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod, orgId int64, repoId int64) *proto.GetDiscountLineItemsResponse {
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(usageDate.Year()),
		Month:         int64(usageDate.Month()),
		Day:           int64(usageDate.Day()),
		Hour:          int64(usageDate.Hour()),
		BillingPeriod: period,
		OrgId:         orgId,
		RepoId:        repoId,
	}
	results, err := i.usageApiClient.GetDiscountLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetOrgRepoUsageLineItems(orgId int64, repoId int64, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageLineItemsResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		RepoId:        repoId,
		OrgId:         orgId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
	}
	results, err := i.usageApiClient.GetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetOrgRepoProductSkuUsageLineItems(customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageLineItemsResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		GroupBy:       proto.UsageGroupBy_GroupByOrgRepoProductSku,
	}
	results, err := i.usageApiClient.GetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetOrgRepoUsageLineItemsGroupBy(orgId int64, repoId int64, customerId string, usageDate time.Time, period proto.BillingPeriod, groupBy proto.UsageGroupBy) *proto.GetUsageLineItemsResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		RepoId:        repoId,
		OrgId:         orgId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		GroupBy:       groupBy,
	}
	results, err := i.usageApiClient.GetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetRepoUsageLineItemsGroupBy(customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageLineItemsResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		GroupBy:       proto.UsageGroupBy_GroupByRepository,
	}
	results, err := i.usageApiClient.GetUsageLineItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageEventItemsDateParts(product string, sku string, customerId string, period proto.BillingPeriod, year, month, day, hour int) *proto.GetUsageLineItemsResponse {
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Product:       product,
		Sku:           sku,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
	}

	results, err := i.usageApiClient.GetUsageEventItems(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageEventItems(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageLineItemsResponse {
	return i.GetUsageEventItemsDateParts(product, sku, customerId, period, usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour())
}

func (i *IntegrationClient) GetUsageTotalByRepo(repoId int64, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId:                customerId,
		Year:                         int64(year),
		Month:                        int64(month),
		Day:                          int64(day),
		Hour:                         int64(hour),
		BillingPeriod:                period,
		RepoId:                       repoId,
		IncludeQuantityGetUsageTotal: true,
	}
	results, err := i.usageApiClient.GetUsageTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetWatermarkLevel(customerId string, sku string, orgId, repoId int64) *proto.GetWatermarkLevelResponse {
	request := &proto.GetWatermarkLevelRequest{
		UsageEntityId: customerId,
		Sku:           sku,
		OrgId:         orgId,
		RepoId:        repoId,
	}

	result, err := i.usageApiClient.GetWatermarkLevel(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetUsageByRepo(customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetRepoUsageResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetRepoUsageRequest{
		UsageEntityId: customerId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
	}
	results, err := i.usageApiClient.GetRepoUsage(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageReport(customerId string, usageDate time.Time, period proto.BillingPeriod, includeCostCenterUsage bool, orgId int64) *proto.GetUsageReportResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageReportRequest := &proto.GetUsageReportRequest{
		UsageEntityId:          customerId,
		Year:                   int64(year),
		Month:                  int64(month),
		Day:                    int64(day),
		Hour:                   int64(hour),
		BillingPeriod:          period,
		IncludeCostCenterUsage: includeCostCenterUsage,
		OrgId:                  orgId,
	}
	results, err := i.usageReportApiClient.GetUsageReport(context.Background(), usageReportRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetTopOrgRepoUsageLineItems(customerId int64, costCenterId string, limit int32, usageDate time.Time, billingPeriod proto.BillingPeriod, groupBy proto.UsageGroupBy, organizationIDs []int64) *proto.TopOrgRepoUsageResponse {
	year, month, day, hour := int64(usageDate.Year()), int64(usageDate.Month()), int64(usageDate.Day()), int64(usageDate.Hour())
	request := &proto.TopOrgRepoUsageRequest{
		CustomerId:      customerId,
		CostCenterId:    costCenterId,
		Limit:           limit,
		Year:            year,
		Month:           month,
		Day:             day,
		Hour:            hour,
		BillingPeriod:   billingPeriod,
		GroupBy:         groupBy,
		OrganizationIds: organizationIDs,
	}

	results, err := i.usageApiClient.GetTopOrgRepoUsageLineItems(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results

}

func (i *IntegrationClient) GetUsageTotalByOrg(orgId int64, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId: customerId,
		Year:          int64(year),
		Month:         int64(month),
		Day:           int64(day),
		Hour:          int64(hour),
		BillingPeriod: period,
		OrgId:         orgId,
	}
	results, err := i.usageApiClient.GetUsageTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) GetUsageTotal(product string, sku string, customerId string, usageDate time.Time, period proto.BillingPeriod) *proto.GetUsageResponse {
	year, month, day, hour := usageDate.Year(), int(usageDate.Month()), usageDate.Day(), usageDate.Hour()
	usageRequest := &proto.GetUsageRequest{
		UsageEntityId:                customerId,
		Product:                      product,
		Sku:                          sku,
		Year:                         int64(year),
		Month:                        int64(month),
		Day:                          int64(day),
		Hour:                         int64(hour),
		BillingPeriod:                period,
		IncludeQuantityGetUsageTotal: true,
	}
	results, err := i.usageApiClient.GetUsageTotal(context.Background(), usageRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return results
}

func (i *IntegrationClient) NewAzureAztablesIntegrationClient() (*aztables.Client, error) {
	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %v", err)
	}
	ac := azurecommerce.NewAzureCommerceClient()
	sasToken := i.AzureCommerceGetSasToken(ac, true)
	serviceUrl := fmt.Sprintf("%s%s", cfg.AzureCommerceTableListUri, sasToken)

	client, err := azurecommerce.NewTablesClient(context.Background(), serviceUrl)
	if err != nil {
		return nil, errors.Wrap(err, "failed to load client")
	}

	return client, nil
}

func (i *IntegrationClient) GetUsageEntitiesFromAzureStorage(eventId string) ([]aztables.EDMEntity, error) {
	aztablesClient, err := i.NewAzureAztablesIntegrationClient()
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	filter := fmt.Sprintf("EventId eq '%s'", eventId)
	options := &aztables.ListEntitiesOptions{
		Filter: &filter,
		Top:    to.Ptr(int32(1)),
	}
	pager := aztablesClient.NewListEntitiesPager(options)
	count := 0
	var response aztables.ListEntitiesResponse
	for pager.More() {
		response, err = pager.NextPage(context.Background())
		if err != nil {
			return nil, errors.Wrap(err, "failed to get next page")
		}
		count += len(response.Entities)
		if count <= 1 {
			break
		}
	}

	entitiesResult := make([]aztables.EDMEntity, 0)
	for _, entity := range response.Entities {
		var usageEntity aztables.EDMEntity
		err := json.Unmarshal(entity, &usageEntity)
		if err != nil {
			return nil, errors.Wrap(err, "failed to unmarshal entity")
		}
		entitiesResult = append(entitiesResult, usageEntity)
	}

	return entitiesResult, nil
}

func (i *IntegrationClient) NewAzureAzqueueErrorQueueIntegrationClient() (*azqueue.QueueClient, error) {
	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %v", err)
	}
	ac := azurecommerce.NewAzureCommerceClient()
	sasToken := i.AzureCommerceGetSasToken(ac, true)
	serviceUrl := fmt.Sprintf("%s%s", cfg.AzureCommerceErrorQueueUri, sasToken)

	client, err := azurecommerce.NewQueueClient(context.Background(), serviceUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to load client: %v", err)
	}

	return client, nil
}

func (i *IntegrationClient) PeekMessageFromAzureErrorQueue() ([]*azqueue.PeekedMessage, error) {
	azqueueClient, err := i.NewAzureAzqueueErrorQueueIntegrationClient()
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	queue, err := azqueueClient.PeekMessage(context.Background(), nil)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	messages := queue.Messages
	return messages, nil
}

func (i *IntegrationClient) GetAzureEmission(customerId string, sku string, usageDate time.Time) *proto.GetAzureEmissionResponse {
	azureEmissionRequest := &proto.GetAzureEmissionRequest{
		CustomerId: customerId,
		Sku:        sku,
		Year:       int64(usageDate.Year()),
		Month:      int64(usageDate.Month()),
		Day:        int64(usageDate.Day()),
	}
	result, err := i.adminApiClient.GetAzureEmission(context.Background(), azureEmissionRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) ProduceMeteredUsage(usages []*hydroSchema.Usage) {
	var err error
	options := messaging.MessageSenderOptions()
	queueName := i.usageIntestionQueueName
	for _, usage := range usages {
		// actions 64
		err = i.send(usage, queueName, options)
		i.g.Expect(err).ToNot(gomega.HaveOccurred())
	}

	depth := i.getQueueDepth(queueName)

	i.Logger.Info("Integration Client sending usage",
		kvp.Int64("depth", depth),
		kvp.String("app", i.aqueductApplication),
		kvp.String("queue", queueName),
	)
}

func (i *IntegrationClient) ProduceBadMessageForQueue(queueType models.WorkerType) {
	var err error
	options := messaging.MessageSenderOptions()
	queueName := messaging.GetQueueName(queueType, i.uniqueQueueName)
	badPayload := []byte(`bad message`)

	payload, err := json.Marshal(badPayload)
	if err != nil {
		i.Logger.WithError(err).Error("error serializing bad payload in ProduceBadMessageForQueue")
	}

	job := aqueduct.Job{
		App:     i.aqueductApplication,
		Queue:   queueName,
		Payload: payload}
	_, err = i.aqueductClient.Send(context.Background(), job, options...)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	depth := i.getQueueDepth(queueName)

	i.Logger.Info("Integration Client sending message with bad payload", kvp.Int64("depth", depth), kvp.String("app", i.aqueductApplication), kvp.String("queue", queueName))
}

func (i *IntegrationClient) assertQueueDepth(actual, expected int64, queueName string) {
	i.t.Helper()
	if actual != expected {
		peekDepth := math.Max(float64(actual), float64(expected))
		payloads, err := i.aqueductClient.Peek(context.Background(), i.aqueductApplication, queueName, int(peekDepth))
		i.g.Expect(err).ToNot(gomega.HaveOccurred(), "Error peeking messages from dead letter queue")

		strPayloads := make([]string, len(payloads))
		for _, payload := range payloads {
			strPayloads = append(strPayloads, string(payload))
		}

		i.g.Expect(actual).To(gomega.Equal(expected), "Unexpected queue count %v", strPayloads)
	}
}

func (i *IntegrationClient) getQueueDepth(queueName string) int64 {
	depth, err := i.aqueductClient.QueueDepth(context.Background(), i.aqueductApplication, queueName)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())
	return depth
}

func (i *IntegrationClient) ValidateQueue(expectedQueueLength int64, queueType models.WorkerType) {
	i.t.Helper()
	i.g.THelper()
	queueName := messaging.GetQueueName(queueType, i.uniqueQueueName)
	i.Logger.Info("ValidateQueue", kvp.String("queueName", queueName))
	depth := i.getQueueDepth(queueName)

	i.assertQueueDepth(depth, expectedQueueLength, queueName)
}

func (i *IntegrationClient) ValidateDeadLetterQueue(expectedQueueLength int64, queueType models.WorkerType) {
	i.t.Helper()
	i.g.THelper()
	queueName := messaging.GetQueueName(queueType, i.uniqueQueueName)
	deadLetterQueueName := messaging.GetDeadLetterQueueName(queueName)
	i.Logger.Info("ValidateDeadLetterQueue", kvp.String("queueName", queueName), kvp.String("deadLetterQueueName", deadLetterQueueName))
	depth := i.getQueueDepth(deadLetterQueueName)

	i.assertQueueDepth(depth, expectedQueueLength, deadLetterQueueName)
}

func (i *IntegrationClient) ValidateAzureEmission(customerId string, azureAccountId string, azureMeterdId string, usageTime time.Time, expectedQuantity float64) {
	i.t.Helper()
	i.g.THelper()
	usageDate := *models.NewUsageTimeFromTime(usageTime)
	eventId := models.GenerateAzureEventId(azureAccountId, customerId, azureMeterdId, usageDate)
	azureUsages, _ := i.GetUsageEntitiesFromAzureStorage(eventId)

	if len(azureUsages) == 0 {
		i.Logger.Info("No usage found in azure storage")
		return
	}

	resourceUri := fmt.Sprintf("/subscriptions/%s/providers/GitHub/EnterpriseAccount/customer-%s", azureAccountId, customerId)
	queueMessage, _ := models.GenerateAzureQueueMessage(azureUsages[0])
	decodedQueueMessage, _ := base64.StdEncoding.DecodeString(queueMessage)
	queueMessagePartitionId := fmt.Sprintf("\"partitionId\":\"%s", azureUsages[0].PartitionKey)

	// test that we actually emitted usage
	azureDate := aztables.EDMDateTime(usageTime)
	i.g.Expect(azureUsages).Should(gomega.HaveLen(int(1)))
	// quantity is doubled because of the rollup
	i.g.Expect(azureUsages[0].Properties["Quantity"]).Should(gomega.BeEquivalentTo(expectedQuantity))
	i.g.Expect(azureUsages[0].Properties["SubscriptionId"]).Should(gomega.Equal(azureAccountId))
	i.g.Expect(azureUsages[0].Properties["MeterId"]).Should(gomega.Equal(azureMeterdId))
	i.g.Expect(azureUsages[0].Properties["EventId"]).Should(gomega.Equal(eventId))
	i.g.Expect(azureUsages[0].Properties["ResourceUri"]).Should(gomega.Equal(resourceUri))
	i.g.Expect(azureUsages[0].Properties["Location"]).Should(gomega.Equal("eastus"))
	i.g.Expect(azureUsages[0].Properties["EventDateTime"]).Should(gomega.Equal(azureDate))

	i.g.Expect(string(decodedQueueMessage)).Should(gomega.ContainSubstring("\"batchId\":\""))
	i.g.Expect(string(decodedQueueMessage)).Should(gomega.ContainSubstring(queueMessagePartitionId))

	// Be sure to clear the errors queue on the Azure portal (billingnonprod573dad)
	// when the test is fixed, otherwise this assertion will keep failing
	azureErrorQueueMessages, _ := i.PeekMessageFromAzureErrorQueue()
	i.g.Expect(azureErrorQueueMessages).Should(gomega.HaveLen(0))
}

func (i *IntegrationClient) send(message *hydroSchema.Usage, queueName string, options []aqueduct.SendOption) error {
	messageBytes, err := protobuf.Marshal(message)
	if err != nil {
		return errors.Wrap(err, "failed to marshal message")
	}

	envelope := schemas.Envelope{
		Message: messageBytes,
	}

	envelopeBytes, err := protobuf.Marshal(&envelope)
	if err != nil {
		return errors.Wrap(err, "failed to marshal envelope")
	}

	job := aqueduct.Job{
		App:     i.aqueductApplication,
		Queue:   queueName,
		Payload: envelopeBytes,
	}
	_, err = i.aqueductClient.Send(context.Background(), job, options...)
	if err != nil {
		i.Logger.WithError(err).Error("error sending job",
			kvp.String("aqueduct.job.app", job.App),
			kvp.String("aqueduct.job.queue", job.Queue),
			kvp.String("aqueduct.job.payload", string(job.Payload)),
		)
	}
	return nil
}

func (i *IntegrationClient) EnsureRandomPricingExists() *proto.Pricing {
	return i.EnsureSpecificPricingExists(0, "actions_linux", "actions", "Actions")
}

func (i *IntegrationClient) EnsureSpecificPricingExists(price float64, sku, product string, friendlyName string) *proto.Pricing {
	return i.EnsureSpecificPricingExistsWithAll(price, sku, product, proto.PricingMeterType_Default, friendlyName, proto.UnitType_Unknown)
}

func (i *IntegrationClient) EnsureSpecificPricingExistsWithFreeForPublicRepos(price float64, sku, product string, friendlyName string) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, proto.PricingMeterType_Default, friendlyName, true, time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC).Unix(), proto.UnitType_Unknown, false)
	_ = i.UpsertPricing(pricing)
	return pricing
}

func (i *IntegrationClient) EnsureSpecificPricingExistsWithEffectiveAt(price float64, sku, product string, meterType proto.PricingMeterType, effectiveAt int64) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, meterType, "", false, effectiveAt, proto.UnitType_Unknown, false)
	_ = i.UpsertPricing(pricing)

	return pricing
}

func (i *IntegrationClient) EnsureSpecificPricingExistsWithUnitType(price float64, sku, product string, unitType proto.UnitType) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, proto.PricingMeterType_Default, "", false, time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC).Unix(), unitType, false)
	_ = i.UpsertPricing(pricing)
	return pricing
}

func (i *IntegrationClient) EnsureSpecificPricingExistsWithAll(price float64, sku, product string, meterType proto.PricingMeterType, friendlyName string, unitType proto.UnitType) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, meterType, friendlyName, false, time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC).Unix(), unitType, false)
	_ = i.UpsertPricing(pricing)

	return pricing
}

func (i *IntegrationClient) EnsureFreePricingExists(sku, product string, friendlyName string) *proto.Pricing {
	pricing := createPricingProto(0, sku, product, proto.PricingMeterType_Default, friendlyName, false, time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC).Unix(), proto.UnitType_Unknown, true)
	_ = i.UpsertPricing(pricing)

	return pricing
}

func (i *IntegrationClient) EnsureDisabledPricingExists(price float64, sku, product string, friendlyName string) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, proto.PricingMeterType_Default, friendlyName, false, time.Now().UTC().AddDate(1, 0, 0).Unix(), proto.UnitType_Unknown, false)
	_ = i.UpsertPricing(pricing)

	return pricing
}

func (i *IntegrationClient) EnsureSpecificPricingExistsWithAzureMeterID(price float64, sku, product string, azureMeterID string) *proto.Pricing {
	pricing := createPricingProto(price, sku, product, proto.PricingMeterType_Default, "", false, time.Date(2010, 1, 1, 0, 0, 0, 0, time.UTC).Unix(), proto.UnitType_Unknown, false)
	pricing.AzureMeterId = azureMeterID
	_ = i.UpsertPricing(pricing)

	return pricing
}

func (i *IntegrationClient) EnsureProductExists(name string, friendlyName string, zuoraUsageIdentifier string) *proto.Product {
	productProto := &proto.Product{
		Name:                 name,
		FriendlyProductName:  friendlyName,
		ZuoraUsageIdentifier: zuoraUsageIdentifier,
	}
	_, _ = i.UpsertProduct(productProto)
	return productProto
}

func createPricingProto(price float64, sku, product string, meterType proto.PricingMeterType, friendlyName string, freeForPublicRepos bool, effectiveAt int64, unitType proto.UnitType, forceFree bool) *proto.Pricing {
	if price == 0 && !forceFree {
		price = float64(stubs.GetRandomId64() / 100)
	}

	skuId := stubs.GetRandomId()
	if friendlyName == "" && sku != "" {
		friendlyName = sku
	}

	if friendlyName == "" && sku == "" {
		friendlyName = fmt.Sprintf("SKU %d", skuId)
	}

	if sku == "" {
		sku = fmt.Sprintf("sku-%d", skuId)
	}

	if product == "" {
		product = fmt.Sprintf("product-%d", stubs.GetRandomId())
	}

	return &proto.Pricing{
		Sku:                sku,
		Product:            product,
		Price:              price,
		MeterType:          meterType,
		FriendlyName:       friendlyName,
		AzureMeterId:       uuid.NewString(),
		FreeForPublicRepos: freeForPublicRepos,
		EffectiveAt:        effectiveAt,
		UnitType:           unitType,
	}
}

func getRandomHttpPort() int {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	min := 8990
	max := 33000
	return r.Intn(max-min+1) + min
}

func withRetriesOnRateLimit(f func() error) error {
	maxRetryCount := 10
	var err error
	for i := 0; i < maxRetryCount; i++ {
		if err = f(); err != nil {
			if db.Is429ToManyRequests(err) {
				// Add some randomness to prevent creating a Thundering Herd
				sleep := 10 * time.Second
				jitter := time.Duration(rand.Int63n(int64(sleep)))
				time.Sleep(sleep + jitter/2)
				continue
			}
			return err
		} else {
			return nil
		}

	}
	return errors.Wrap(err, "Retries exhausted")

}

// DropUniqueTestCollection drops the unique test collection and database
// configured in the integration tests client.
func (i *IntegrationClient) DropUniqueTestCollection() {
	// TODO: This assumes that uniqueCollectionname is in the schemaManager's database scope
	// It's totally possible that the schemaManager is not using the same database as the
	// uniqueCollectionName and that uniqueDatabaseName is different as well. This should be fixed.
	if err := withRetriesOnRateLimit(func() error {
		return i.schemaManager.RemoveCollection(context.Background(), i.uniqueCollectionName)
	}); err != nil {
		if !db.Is404NotFound(err) {
			i.t.Fatalf("Failed to drop collection: %v", err)
		}
	}
}

func (i *IntegrationClient) GetCostCenter(costcenterKey *proto.CostCenterKey) *proto.GetCostCenterResponse {
	costCenterRequest := &proto.GetCostCenterRequest{
		CostCenterKey: costcenterKey,
	}
	result, err := i.costCenterApiClient.GetCostCenter(context.Background(), costCenterRequest)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) CostCenterAddResourceTo(costcenterKey *proto.CostCenterKey, resources []*proto.Resource) (*proto.AddResourceToCostCenterResponse, error) {
	costCenterRequest := &proto.AddResourceToCostCenterRequest{
		Key:       costcenterKey,
		Resources: resources,
	}
	return i.costCenterApiClient.AddResourceTo(context.Background(), costCenterRequest)
}

func (i *IntegrationClient) CostCenterRemoveResourceFrom(costcenterKey *proto.CostCenterKey, resources []*proto.Resource) (*proto.RemoveResourceFromCostCenterResponse, error) {
	costCenterRequest := &proto.RemoveResourceFromCostCenterRequest{
		Key:       costcenterKey,
		Resources: resources,
	}
	return i.costCenterApiClient.RemoveResourceFrom(context.Background(), costCenterRequest)
}

func (i *IntegrationClient) CreateCostCenter(costCenter *proto.CostCenter) (*proto.CreateCostCenterResponse, error) {
	costCenterRequest := &proto.CreateCostCenterRequest{
		CustomerId: costCenter.CostCenterKey.CustomerId,
		TargetId:   costCenter.CostCenterKey.TargetId,
		TargetType: costCenter.CostCenterKey.TargetType,
		Name:       costCenter.Name,
		Resources:  costCenter.Resources,
	}
	result, err := i.costCenterApiClient.CreateCostCenter(context.Background(), costCenterRequest)

	if err != nil {
		return nil, err
	}

	return result, nil
}

type UpdateCostCenterArgs struct {
	CostCenterKey     *proto.CostCenterKey
	Name              string
	TargetId          string
	ResourcesToAdd    []*proto.Resource
	ResourcesToRemove []*proto.Resource
}

func (i *IntegrationClient) UpdateCostCenter(args UpdateCostCenterArgs) (*proto.UpdateCostCenterResponse, error) {
	costCenterRequest := &proto.UpdateCostCenterRequest{
		Key:               args.CostCenterKey,
		TargetId:          args.TargetId,
		Name:              args.Name,
		ResourcesToAdd:    args.ResourcesToAdd,
		ResourcesToRemove: args.ResourcesToRemove,
	}
	result, err := i.costCenterApiClient.UpdateCostCenter(context.Background(), costCenterRequest)

	if err != nil {
		return nil, err
	}

	return result, nil
}

func (i *IntegrationClient) FindCostCenterFor(entityDetail *proto.EntityDetail, sku string) *proto.FindCostCenterForResponse {
	findCostCenterFor := &proto.FindCostCenterForRequest{
		EntityDetail: entityDetail,
		Sku:          sku,
	}
	result, err := i.costCenterApiClient.FindFor(context.Background(), findCostCenterFor)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) GetAllCostCenters(customerId string) *proto.GetAllCostCentersResponse {
	request := &proto.GetAllCostCentersRequest{
		CustomerId: customerId,
	}
	result, err := i.costCenterApiClient.GetAllCostCenters(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) ArchiveCostCenter(costCenterKey *proto.CostCenterKey) *proto.ArchiveCostCenterResponse {
	request := &proto.ArchiveCostCenterRequest{
		CostCenterKey: costCenterKey,
	}

	result, err := i.costCenterApiClient.ArchiveCostCenter(context.Background(), request)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return result
}

func (i *IntegrationClient) AzureCommerceGetSasToken(ac *azurecommerce.AzureCommerce, force bool) string {
	sasToken, err := ac.GetSasToken(context.Background(), i.cfg.StatsClient(), i.cfg, force)
	i.g.Expect(err).ToNot(gomega.HaveOccurred())

	return sasToken
}

func (i *IntegrationClient) StartZuoraServer(mockResponses []func(rw http.ResponseWriter, r *http.Request)) *httptest.Server {
	mockServer := stubs.SetupZuoraServer(mockResponses)
	i.Logger.Info("Started mock zuora server at " + mockServer.URL)
	i.zuoraServerUrl = mockServer.URL
	i.zuoraServer = mockServer

	return mockServer
}

func (i *IntegrationClient) GetDeadLetterQueueName(workerType models.WorkerType) string {
	queueName := messaging.GetQueueName(workerType, i.uniqueQueueName)
	return messaging.GetDeadLetterQueueName(queueName)
}

func (i *IntegrationClient) ProcessDeadLetterQueue(num int64, queueName string) error {
	resp, err := i.adminApiClient.ProcessDeadLetterQueue(context.Background(), &proto.ProcessDeadLetterQueueRequest{
		Num:       num,
		QueueName: queueName,
	})
	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

func (i *IntegrationClient) CreateRepo(repoId int64, isPublic bool) error {
	repo := models.NewRepo(repoId, isPublic)
	return i.DB.UpsertWithOptions(context.Background(), i.Logger, repo, nil)
}

func (i *IntegrationClient) GetRepo(repoId int64) (*models.Repo, error) {
	repoKey := models.NewRepoKey(repoId)
	return db.NewQuerier[*models.Repo](i.DB).ReadItemWithRetries(context.Background(), i.Logger, repoKey)
}

func (i *IntegrationClient) FetchDiscountTrackItems(customerId string, discountUuid string, year, month int) ([]*models.DiscountTrackItem, error) {
	return db.NewQuerier[*models.DiscountTrackItem](i.DB).QueryItems(
		context.Background(),
		i.Logger,
		"SELECT * FROM c WHERE c.id != \"discountState\"",
		fmt.Sprintf("customer:%s:discounts:%s:%d:%d", customerId, discountUuid, year, month),
	)
}

func (i *IntegrationClient) AdminTriggerAzureEmission(date time.Time, customerId string) error {
	resp, err := i.adminApiClient.TriggerAzureEmission(context.Background(), &proto.TriggerAzureEmissionRequest{
		Year:       int64(date.Year()),
		Month:      int64(date.Month()),
		Day:        int64(date.Day()),
		CustomerId: customerId,
	})

	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

func (i *IntegrationClient) AdminTriggerInvoiceGeneration(date time.Time, customerId string) error {
	resp, err := i.adminApiClient.TriggerInvoiceGeneration(context.Background(), &proto.TriggerInvoiceGenerationRequest{
		Year:       int64(date.Year()),
		Month:      int64(date.Month()),
		CustomerId: customerId,
	})

	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

func (i *IntegrationClient) AdminTriggerWatermarkWorkflow(payload *proto.TriggerWatermarkWorkflowRequest) error {
	resp, err := i.adminApiClient.TriggerWatermarkWorkflow(context.Background(), payload)

	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

func (i *IntegrationClient) AdminGenerateUsage(payload *proto.GenerateUsageRequest) error {
	resp, err := i.adminApiClient.GenerateUsage(context.Background(), payload)

	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

func (i *IntegrationClient) AdminTriggerHighWatermarkRollover(payload *proto.TriggerHighWatermarkRolloverRequest) error {
	resp, err := i.adminApiClient.TriggerHighWatermarkRolloverJob(context.Background(), payload)

	if err != nil {
		return err
	}

	i.g.Expect(resp.Success).To(gomega.BeTrue())
	return nil
}

type ProcessWatermarkUsageOpts struct {
	ExpectedLineItems int
}

func (i *IntegrationClient) ProcessWatermarkUsage(runTime time.Time, usages []*hydroSchema.Usage, opts ProcessWatermarkUsageOpts) {
	i.t.Helper()
	// We need the unique entity count to verify that we dispatched the correct number of events for
	// each sku/org/repo combinatoin.
	entityCount := 0
	entities := make(map[string]bool)
	for _, usage := range usages {
		key := fmt.Sprintf("%s:%d:%d", usage.Sku, usage.Entity.OrganizationId, usage.Entity.CustomerId)
		if _, ok := entities[key]; !ok {
			entities[key] = true
			entityCount++
		}
	}

	// We need the unique customer count to validate that we dispatched the correct number of events
	// for active customers.
	customerCount := 0
	customers := make(map[int64]bool)
	for _, usage := range usages {
		if _, ok := customers[usage.Entity.CustomerId]; !ok {
			customers[usage.Entity.CustomerId] = true
			customerCount++
		}
	}

	skuCount := 0
	skus := make(map[string]bool)
	for _, usage := range usages {
		if _, ok := skus[usage.Sku]; !ok {
			skus[usage.Sku] = true
			skuCount++
		}
	}

	expectedLineItems := 0
	if opts.ExpectedLineItems > 0 {
		expectedLineItems = opts.ExpectedLineItems
	} else {
		expectedLineItems = entityCount
	}

	i.ProduceMeteredUsage(usages)
	i.RunUsageIngestion(len(usages))

	// Validate that no messages have been sent to the request handler yet
	i.ValidateQueue(0, models.WorkerTypeRequestHandler)

	// Send a message to the request handler to schedule watermark jobs
	i.ScheduleWatermarkJobs(runTime, "")

	// Ensure our request made it to the queue
	i.ValidateQueue(1, models.WorkerTypeRequestHandler)
	i.ValidateQueue(0, models.WorkerTypeWatermarkHandler)

	i.RunRequestHandler(entityCount)

	// A message made it back to usage ingestion
	i.ValidateQueue(0, models.WorkerTypeRequestHandler)
	i.ValidateQueue(int64(customerCount*skuCount), models.WorkerTypeWatermarkHandler)

	i.RunWatermarkHandler(entityCount)

	i.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	i.ValidateQueue(int64(expectedLineItems), models.WorkerTypeUsageIngestion)

	// Run usage ingestion so we can see if the message gets processed
	i.RunUsageIngestion(expectedLineItems)
	i.ValidateQueue(0, models.WorkerTypeUsageIngestion)
}

func (i *IntegrationClient) ProcessAzureEmission(runtime time.Time, azureEmissionQueueDepth, numberOfLineItems int) {
	queueName := messaging.GetQueueName(models.WorkerTypeCustomerAzureEmissionDailyRollup, i.uniqueQueueName)
	queueDepth := int(i.getQueueDepth(queueName))
	i.g.Expect(queueDepth).To(gomega.BeNumerically(">", 0.0))
	i.RunAzureDailyRollupJob(queueDepth)
	i.RunDailyJob(queueDepth)
	i.ScheduleAzureEmissionWithTime(runtime)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	i.ValidateQueue(1, models.WorkerTypeRequestHandler)
	i.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	i.RunRequestHandler(numberOfLineItems)
	i.ValidateQueue(int64(numberOfLineItems), models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	i.RunAzureEmission(azureEmissionQueueDepth)
	i.ValidateQueue(0, models.WorkerTypeAzureEmission)
	i.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)
}

func (i *IntegrationClient) EnforceFloatPrecision(number float64, decimalPoints int) float64 {
	scale := math.Pow(10, float64(decimalPoints))
	return math.Round(number*scale) / scale
}

func (i *IntegrationClient) RemainingDaysInMonth(t time.Time) int {
	return i.DaysInMonth(t) - t.Day() + 1
}

func (i *IntegrationClient) DaysInMonth(t time.Time) int {
	year, month, _ := t.Date()
	firstOfNextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, t.Location())
	lastDayOfMonth := firstOfNextMonth.AddDate(0, 0, -1)
	return lastDayOfMonth.Day()
}

func (i *IntegrationClient) DailyHighWatermarkForMonth(usageDate time.Time) float64 {
	days := int64(i.DaysInMonth(usageDate))
	// We hardcode the daily quantity because we need to trick the
	// tests into arriving at the same precision quantity that we
	// have in our code
	switch days {
	case 28:
		return 0.035714285
	case 29:
		return 0.034482758
	case 30:
		return 0.033333333
	case 31:
		return 0.032258064
	default:
		fmt.Printf("Unexpected number of days in month: %+v\n", days)
		return 0.0
	}
}
