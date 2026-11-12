package cosmos

import (
	cosmosbase "github.com/github/sweagentd/internal/cosmos"
)

// Opts is an alias for the shared Cosmos DB client options.
//
// Deprecated: Use github.com/github/sweagentd/internal/cosmos.Opts directly.
type Opts = cosmosbase.Opts

// ContainerOpts is an alias for the shared Cosmos DB container client options.
//
// Deprecated: Use github.com/github/sweagentd/internal/cosmos.ContainerOpts directly.
type ContainerOpts = cosmosbase.ContainerOpts

// NewCosmosClient creates a new Cosmos DB client with the provided options.
//
// Deprecated: Use github.com/github/sweagentd/internal/cosmos.NewCosmosClient directly.
var NewCosmosClient = cosmosbase.NewCosmosClient

// NewCosmosContainerClient creates a new Cosmos DB container client with the provided options.
//
// Deprecated: Use github.com/github/sweagentd/internal/cosmos.NewCosmosContainerClient directly.
var NewCosmosContainerClient = cosmosbase.NewCosmosContainerClient
