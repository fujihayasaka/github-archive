// Package http provides HTTP handlers for memory operations
// This package is a "adapter" that connects the core memory service to HTTP requests.
// It also constructs the entire dependency graph for the memory service.
package http

import (
	"fmt"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	memory "github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	memorydotcom "github.com/github/sweagentd/internal/memory/dotcom"
	memorylocal "github.com/github/sweagentd/internal/memory/local"
	secretscanning "github.com/github/sweagentd/internal/memory/secret_scanning"
	"github.com/github/sweagentd/internal/observability"
)

type Dependencies struct {
	memoryService    memory.MemoryService
	memoryRepository memory.MemoryRepository
	HTTPHandler      *MemoryHandler
}

// NewDependencies creates a new Dependencies instance
// It constructs the memory service and all its dependencies based on the configuration
// This allows the HTTP handler to be used in the main application, or to moved to a different package/service if needed.
func NewDependencies(cfg *config.Config, featureFlagClient featureflags.Client, githubClientFactory github.ClientFactoryInterface, obsv observability.Exporters) *Dependencies {
	memoryRepository := memorylocal.NewLocalMemoryRepository()
	repositoryStore := memorydotcom.NewRepositoryStore(githubClientFactory, obsv)

	if !cfg.IsDevelopment() {
		// If we are not in development and Cosmos DB is enabled, use the Cosmos memory repository
		var err error
		memoryRepository, err = cosmos.NewCosmosMemoryRepository(&cosmos.CosmosContainerOpts{
			DatabaseID:  cfg.AzureCosmosDBDatabase,
			ContainerID: cfg.AzureCosmosDBContainerMemory,
			CosmosOpts: cosmos.CosmosOpts{
				ConnectionString:             cfg.AzureCosmosDBConnectionString,
				Endpoint:                     cfg.AzureCosmosDBEndpoint,
				Obsv:                         obsv,
				AzureCosmosDBSPNTenantID:     cfg.AzureCosmosDBSPNTenantID,
				AzureCosmosDBSPNClientID:     cfg.AzureCosmosDBSPNClientID,
				AzureCosmosDBSPNClientSecret: cfg.AzureCosmosDBSPNClientSecret,
			},
		})
		if err != nil {
			panic(fmt.Errorf("failed to create Cosmos memory repository: %w", err))
		}
	}
	secretScanner := secretscanning.NewSecretScanner(cfg.TokenScanningURL, cfg.TokenScanningHMACKey)
	memoryService := memory.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, obsv)
	memoryHandler := NewMemoryHandler(memoryService, githubClientFactory, obsv)

	return &Dependencies{
		memoryService:    memoryService,
		memoryRepository: memoryRepository,
		HTTPHandler:      memoryHandler,
	}
}
