package cosmosdb

import (
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
			obsv.Logger.Info("using Cosmos DB emulator for job store")
			return emulatorJobStore, nil
		}

		obsv.Logger.WithError(emulatorErr).Warn("failed to connect to Cosmos DB emulator, falling back to in-memory job store — data will not persist and Cosmos-specific behavior (ETags, partitioning, race conditions) will not be exercised")
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
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to create CosmosDB job store: %w", err)
	}
	return jobStore, nil
}
