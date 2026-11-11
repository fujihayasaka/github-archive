// Package memoryhttp provides HTTP handlers for memory operations
// This package is a "adapter" that connects the core memory service to HTTP requests.
// It also constructs the entire dependency graph for the memory service.
package memoryhttp

import (
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	memorylocal "github.com/github/sweagentd/internal/memory/local"
	secretscanning "github.com/github/sweagentd/internal/memory/secret_scanning"
	"github.com/github/sweagentd/internal/observability"
)

// Dependencies holds all the dependencies required for the memory HTTP handlers.
type Dependencies struct {
	memoryService    core.MemoryService
	memoryRepository core.MemoryRepository
	HTTPHandler      *MemoryHandler
}

// NewDependencies creates a new Dependencies instance
// It constructs the memory service and all its dependencies based on the configuration
// This allows the HTTP handler to be used in the main application, or to moved to a different package/service if needed.
func NewDependencies(
	cfg *config.Config,
	featureFlagClient featureflags.Client,
	githubClientFactory github.ClientFactoryInterface,
	obsv observability.Exporters,
	appProvider *agenticapp.Provider,
	memoryEnablement core.MemoryEnablementChecker,
) *Dependencies {
	memoryRepository := memorylocal.NewLocalMemoryRepository()
	if !cfg.IsDevelopment() {
		// If we are not in development and Cosmos DB is enabled, use the Cosmos memory repository
		var err error
		memoryRepository, err = cosmos.NewCosmosMemoryRepository(&cosmos.ContainerOpts{
			DatabaseID:  cfg.AzureCosmosDBDatabase,
			ContainerID: cfg.AzureCosmosDBContainerMemory,
			Opts: cosmos.Opts{
				ConnectionString:             cfg.AzureCosmosDBConnectionString,
				Endpoint:                     cfg.AzureCosmosDBEndpoint,
				Obsv:                         obsv,
				AzureCosmosDBSPNTenantID:     cfg.AzureCosmosDBSPNTenantID,
				AzureCosmosDBSPNClientID:     cfg.AzureCosmosDBSPNClientID,
				AzureCosmosDBSPNClientSecret: cfg.AzureCosmosDBSPNClientSecret,
			},
		})
		if err != nil {
			panic(goerrors.Errorf("failed to create Cosmos memory repository: %w", err))
		}
	}
	secretScanner := secretscanning.NewSecretScanner(cfg.TokenScanningURL, cfg.TokenScanningHMACKey)
	memoryService := core.NewMemoryService(memoryRepository, featureFlagClient, secretScanner, obsv, memoryEnablement)
	memoryHandler := NewMemoryHandler(memoryService, githubClientFactory, obsv, appProvider)

	return &Dependencies{
		memoryService:    memoryService,
		memoryRepository: memoryRepository,
		HTTPHandler:      memoryHandler,
	}
}
