// Package integration contains the integration tests that run against a live CosmosDB container.
package integration

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	aqueductPkg "github.com/github/licensify/internal/aqueduct"
	aqueductHandlers "github.com/github/licensify/internal/aqueduct/handlers"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/internal/twirpserver"
	customersv1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel/trace"
)

// Client contains the resources needed to run integration tests against a live CosmosDB.
type Client struct {
	DB             *cosmos.DatabaseConnection
	Logger         log.Logger
	AqueductClient aqueduct.Client
	t              *testing.T
	Config         *config.Config
	errorReporter  *exceptions.Reporter
	Statter        stats.Client
	Tracer         trace.Tracer
	EventHandler   *eventhandlers.EventHandler
}

// NewTestClient returns a new Client for running integration tests with a live CosmosDB container.
// It creates a DB named `<user>-<uuid>` and container `<uuid>`, which are deleted when the calling test has finished running.
func NewTestClient(t *testing.T) *Client {
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}
	errorReporter, err := cfg.NewExceptionReporter()
	if err != nil {
		t.Fatalf("failed to create exception reporter: %v", err)
	}

	statter := cfg.StatsClient()

	telem, err := telemetry.NewFromEnv()
	logger := cfg.ConfigureLogger(telem.Logger, "").WithFields(kvp.String("test", cfg.ContainerName))
	tracer := telem.Tracer.Tracer

	if err != nil {
		t.Fatalf("failed to configure telemetry: %v", err)
	}

	cfg.DatabaseName = fmt.Sprintf("%s-%s", os.Getenv("GITHUB_USER"), uuid.NewString())
	cfg.ContainerName = uuid.NewString()

	db, err := cosmos.NewDatabaseConnection(context.Background(), cfg, logger, stats.NullStatter)
	if err != nil {
		t.Fatalf("failed to create database connection: %v", err)
	}

	aqueductClient, err := aqueductPkg.NewClient(cfg.AqueductURL, cfg.AqueductAPIKey, cfg.AqueductAPIKeyVersion, statter)
	if err != nil {
		t.Fatalf("failed to create aqueduct client: %v", err)
	}

	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: aqueductClient}

	eventHandler, err := eventhandlers.NewEventHandler(db, jobby, &monolith.Client{}, statter, tracer)
	if err != nil {
		t.Fatalf("failed to create event handler: %v", err)
	}

	client := &Client{
		t:              t,
		DB:             db,
		Logger:         logger,
		Config:         cfg,
		errorReporter:  errorReporter,
		Statter:        statter,
		Tracer:         tracer,
		EventHandler:   eventHandler,
		AqueductClient: aqueductClient,
	}
	t.Cleanup(client.Cleanup)
	return client
}

// Cleanup deletes the test CosmosDB container and database.
func (c *Client) Cleanup() {
	ctx := context.Background()
	c.Logger.Info("Cleaning up database", kvp.String("database", c.Config.DatabaseName), kvp.String("container", c.Config.ContainerName))
	_, err := c.DB.ContainerClient.Delete(ctx, nil)
	if err != nil {
		c.Logger.WithError(err).Error("failed to delete container")
	}
	_, err = c.DB.DatabaseClient.Delete(ctx, nil)
	if err != nil {
		c.Logger.WithError(err).Error("failed to delete database")
	}
}

// StartTwirpServer starts a new twirp server using httptest and returns the protobuf clients for the twirp services.
func (c *Client) StartTwirpServer() (proto.CustomerLicenseService, proto.ProductEnablementService, proto.CustomerService, *httptest.Server) {
	ctx := context.Background()
	hooks := twirpserver.DefaultHooks(c.Logger, c.errorReporter, c.Statter)
	handler, err := twirpserver.NewTwirpServer(ctx, c.Config, c.Logger, c.Statter, c.Tracer, c.DB, hooks, c.AqueductClient)
	if err != nil {
		c.t.Fatalf("failed to create twirp server: %v", err)
	}

	testServer := httptest.NewServer(handler)
	c.Logger.Info("Started test server", kvp.String("url", testServer.URL))

	customerLicenseServiceClient := proto.NewCustomerLicenseServiceProtobufClient(
		testServer.URL, testServer.Client(),
	)
	productEnablementServiceClient := proto.NewProductEnablementServiceProtobufClient(
		testServer.URL, testServer.Client(),
	)
	customerServiceClient := proto.NewCustomerServiceProtobufClient(
		testServer.URL, testServer.Client(),
	)
	c.t.Cleanup(func() {
		testServer.Close()
		c.Logger.Info("Closed test server")
	})
	return customerLicenseServiceClient, productEnablementServiceClient, customerServiceClient, testServer
}

// NewSyncOrgMembershipsHandler returns a new SyncOrgMembershipsHandler for testing the aqueduct handler.
func (c *Client) NewSyncOrgMembershipsHandler(monolithClient *monolith.Client) *aqueductHandlers.SyncOrgMembershipsHandler {
	customerEngine := engines.NewCustomerEngine(c.Statter, c.Tracer, c.DB)
	customerLicenseEngine := engines.NewCustomerLicenseEngine(c.Statter, c.Tracer, c.DB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(c.Statter, c.Tracer, c.DB)
	return aqueductHandlers.NewSyncOrgMembershipsHandler(customerEngine, customerLicenseEngine, licenseeLicenseEngine, monolithClient, c.Statter, c.Tracer)
}

// NewDeleteEnablementsHandler returns a new DeleteEnablementsHandler for testing the aqueduct handler.
func (c *Client) NewDeleteEnablementsHandler() *aqueductHandlers.DeleteEnablementsHandler {
	customerLicenseEngine := engines.NewCustomerLicenseEngine(c.Statter, c.Tracer, c.DB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(c.Statter, c.Tracer, c.DB)
	customerEngine := engines.NewCustomerEngine(c.Statter, c.Tracer, c.DB)
	return aqueductHandlers.NewDeleteEnablementsHandler(c.Statter, c.Tracer, customerLicenseEngine, licenseeLicenseEngine, customerEngine)
}

// NewCreateRepositoryCollaboratorsHandler returns a new CreateRepositoryCollaboratorsHandler for testing the aqueduct handler.
func (c *Client) NewCreateRepositoryCollaboratorsHandler(monolithClient *monolith.Client) *aqueductHandlers.CreateRepositoryCollaboratorsHandler {
	customerLicenseEngine := engines.NewCustomerLicenseEngine(c.Statter, c.Tracer, c.DB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(c.Statter, c.Tracer, c.DB)
	return aqueductHandlers.NewCreateRepositoryCollaboratorsHandler(c.Statter, c.Tracer, monolithClient, customerLicenseEngine, licenseeLicenseEngine)
}

// StartMonolithTwirpServer starts a new monolith twirp server using httptest and returns the monolith client and the mock organization members API.
func (c *Client) StartMonolithTwirpServer() (*monolith.Client, *mocks.MockMonolithAPI) {
	mockAPI := &mocks.MockMonolithAPI{}
	mux := http.NewServeMux()
	mux.Handle(customersv1.UsersAPIPathPrefix, customersv1.NewUsersAPIServer(mockAPI))
	mux.Handle(repositoriesv1.RepositoriesAPIPathPrefix, repositoriesv1.NewRepositoriesAPIServer(mockAPI))

	monolithServer := httptest.NewServer(mux)
	c.Logger.Info("Started monolith server", kvp.String("url", monolithServer.URL))

	monolithClient, err := monolith.NewClient(monolithServer.URL, c.Config.MonolithTwirpHMACKey)
	require.NoError(c.t, err)

	c.t.Cleanup(func() {
		monolithServer.Close()
		c.Logger.Info("Closed monolith server")
	})

	return monolithClient, mockAPI
}

// NewCustomerLicenseEngine returns a new CustomerLicenseEngine for testing customer licenses.
func (c *Client) NewCustomerLicenseEngine() *engines.CustomerLicenseEngine {
	return engines.NewCustomerLicenseEngine(c.Statter, c.Tracer, c.DB)
}

// NewLicenseeLicenseEngine returns a new LicenseeLicenseEngine for testing licensee licenses.
func (c *Client) NewLicenseeLicenseEngine() *engines.LicenseeLicenseEngine {
	return engines.NewLicenseeLicenseEngine(c.Statter, c.Tracer, c.DB)
}
