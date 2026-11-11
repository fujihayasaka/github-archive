package cosmosdb

import (
	"fmt"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
)

// NewStoreFromConfig creates a new job store, configured according to the environment.
func NewStoreFromConfig(cfg *config.Config) (jobStore store.JobsStore, err error) {
	if cfg.IsDevelopment() {
		// In development, try the Cosmos emulator before falling back to memory store
		emulatorJobStore, emulatorErr := TryCosmosEmulator(cfg)
		if emulatorErr == nil {
			fmt.Println("Using Cosmos DB emulator for job store")
			return emulatorJobStore, nil
		}

		fmt.Printf("Failed to connect to Cosmos DB emulator (%v), falling back to memory store\n", emulatorErr)
		jobStore = memory.NewStore()
		return jobStore, nil
	}

	jobStore, err = NewCosmosJobStore(&CosmosJobStoreOpts{
		Endpoint:               cfg.AzureCosmosDBEndpoint,
		ConnectionString:       cfg.AzureCosmosDBConnectionString,
		DatabaseId:             cfg.AzureCosmosDBDatabase,
		AssignmentsContainerId: cfg.AzureCosmosDBContainerAssignment,
		JobsContainerId:        cfg.AzureCosmosDBContainerJobs,
		CommandsContainerId:    cfg.AzureCosmosDBContainerCommands,
		SPNTenantID:            cfg.AzureCosmosDBSPNTenantID,
		SPNClientID:            cfg.AzureCosmosDBSPNClientID,
		SPNClientSecret:        cfg.AzureCosmosDBSPNClientSecret,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create CosmosDB job store: %w", err)
	}
	return jobStore, nil
}
