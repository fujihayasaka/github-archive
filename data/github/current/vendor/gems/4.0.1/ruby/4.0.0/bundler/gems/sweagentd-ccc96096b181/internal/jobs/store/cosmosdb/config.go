package cosmosdb

import (
	"fmt"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
)

// NewStoreFromConfig creates a new job store, configured according to the environment.
func NewStoreFromConfig(obsv observability.Exporters, cfg *config.Config) (jobStore store.JobsStore, err error) {
	if cfg.IsDevelopment() {
		// In development, try the Cosmos emulator before falling back to memory store
		emulatorJobStore, emulatorErr := TryCosmosEmulator(obsv, cfg)
		if emulatorErr == nil {
			fmt.Println("Using Cosmos DB emulator for job store")
			return emulatorJobStore, nil
		}

		fmt.Printf("Failed to connect to Cosmos DB emulator (%v), falling back to memory store\n", emulatorErr)
		jobStore = memory.NewStore()
		return jobStore, nil
	}

	jobStore, err = NewCosmosJobStore(obsv, &CosmosJobStoreOpts{
		Endpoint:               cfg.AzureCosmosDBEndpoint,
		ConnectionString:       cfg.AzureCosmosDBConnectionString,
		DatabaseID:             cfg.AzureCosmosDBDatabase,
		AssignmentsContainerID: cfg.AzureCosmosDBContainerAssignment,
		JobsContainerID:        cfg.AzureCosmosDBContainerJobs,
		CommandsContainerID:    cfg.AzureCosmosDBContainerCommands,
		ProgressContainerID:    cfg.AzureCosmosDBContainerProgress,
		SPNTenantID:            cfg.AzureCosmosDBSPNTenantID,
		SPNClientID:            cfg.AzureCosmosDBSPNClientID,
		SPNClientSecret:        cfg.AzureCosmosDBSPNClientSecret,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to create CosmosDB job store: %w", err)
	}
	return jobStore, nil
}
