package integration

import (
	"context"
	"testing"

	adminServer "github.com/github/billing-platform/admin"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
	//nolint:staticcheck
)

type IntegrationAdminClient struct {
	AdminServer  *adminServer.AdminServer
	ReadWriteDB  interfaces.Database
	ReadOnlyDB   interfaces.Database
	t            *testing.T
	cfg          *config.Config
	localhost    string
	Logger       *IntegrationLogger
	Flagger      *vexi.Client
	preserveData bool
	g            *gomega.GomegaWithT
}

func NewTestAdminClient(t *testing.T, opts ClientOptions) (*IntegrationAdminClient, *gomega.GomegaWithT) {
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

	file, err := getLogFile("admin-test.log")
	if err != nil {
		t.Fatalf("Failed to open log file: %v", err)
	}

	var uniqueDatabaseName string
	if opts.DatabaseName != "" {
		uniqueDatabaseName = opts.DatabaseName
	} else {
		uniqueDatabaseName = DefaultClientOptions.DatabaseName
	}
	uniqueCollectionName := uuid.NewString()
	uniqueQueueName := uniqueCollectionName

	cfgCopy.DatabaseName = uniqueDatabaseName
	cfgCopy.OverrideQueuePrefix = uniqueQueueName

	if opts.UseExistingData {
		opts.PreserveData = true
		// If useExistingData is true use the global config
		uniqueCollectionName = cfgCopy.ContainerName
	} else {
		// If useExistingData is false, override the config with the unique values
		cfgCopy.ContainerName = uniqueCollectionName
	}

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
	vexiFakeAdapter := fake.NewFakeAdapter(false)
	flagger, _ := vexi.NewClient(context.Background(), vexiFakeAdapter)
	if err != nil {
		t.Fatalf("Failed to create feature flag client: %v", err)
	}

	readWriteDB := db.NewDatabase(&cfgCopy, logger, statter, tracer)
	readOnlyDB, _ := db.NewReadOnlyDatabase(&cfgCopy, logger, statter, tracer)

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

	localServer := "http://localhost:8888"

	g := gomega.NewGomegaWithT(t)
	client := &IntegrationAdminClient{
		AdminServer:  adminServer.NewAdminServer(logger, statter, nil, flagger, readOnlyDB.GetConnection(), cfgCopy.ContainerName, cfgCopy.OktaHMACSecret, cfgCopy.Environment),
		ReadWriteDB:  readWriteDB,
		ReadOnlyDB:   readOnlyDB,
		t:            t,
		cfg:          &cfgCopy,
		Logger:       logger,
		Flagger:      flagger,
		localhost:    localServer,
		preserveData: opts.PreserveData,
		g:            g,
	}

	return client, g
}
