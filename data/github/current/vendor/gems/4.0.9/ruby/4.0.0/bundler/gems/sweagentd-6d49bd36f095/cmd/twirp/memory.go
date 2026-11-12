package main

import (
	"context"
	"sync"

	"github.com/github/sweagentd/internal/config"
	cosmosbase "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	memorylocal "github.com/github/sweagentd/internal/memory/local"
	secretscanning "github.com/github/sweagentd/internal/memory/secret_scanning"
	"github.com/github/sweagentd/internal/observability"
)

type billingEntityMemoryService interface {
	ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error)
	DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error)
}

type lazyMemoryService struct {
	obsv observability.Exporters
	init func() (billingEntityMemoryService, error)

	mu      sync.Mutex
	service billingEntityMemoryService
}

func newLazyMemoryService(
	cfg *config.Config,
	featureFlagClient featureflags.Client,
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
) *lazyMemoryService {
	return &lazyMemoryService{
		obsv: obsv,
		init: func() (billingEntityMemoryService, error) {
			return newMemoryService(cfg, featureFlagClient, obsv, ghTwirp)
		},
	}
}

func (s *lazyMemoryService) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	service, err := s.get(ctx)
	if err != nil {
		return nil, err
	}
	return service.ListBillingEntityMemories(ctx, filter, pageRequest)
}

func (s *lazyMemoryService) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	service, err := s.get(ctx)
	if err != nil {
		return nil, err
	}
	return service.DeleteBillingEntityMemories(ctx, filter, pageRequest)
}

func (s *lazyMemoryService) get(ctx context.Context) (billingEntityMemoryService, error) {
	service, err := s.getOrInit()
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "failed to initialize Twirp memory service")
		return nil, err
	}
	return service, nil
}

func (s *lazyMemoryService) getOrInit() (billingEntityMemoryService, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	service := s.service
	if service == nil {
		var err error
		service, err = s.init()
		if err == nil && service == nil {
			err = goerrors.New("memory service initializer returned nil")
		}
		if err == nil {
			s.service = service
		}
		if err != nil {
			return nil, err
		}
	}
	return service, nil
}

func newMemoryService(
	cfg *config.Config,
	featureFlagClient featureflags.Client,
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
) (core.MemoryService, error) {
	var memoryStore core.MemoryStore
	if cfg.IsDevelopment() {
		memoryStore = memorylocal.NewLocalMemoryStore()
		obsv.Logger.Warn("using in-memory store for agent memory — memory data will not persist across restarts")
	} else {
		var err error
		memoryStore, err = cosmos.NewCosmosMemoryStore(&cosmosbase.ContainerOpts{
			DatabaseID:  cfg.AzureCosmosDBDatabase,
			ContainerID: cfg.AzureCosmosDBContainerMemory,
			Opts: cosmosbase.Opts{
				ConnectionString:         cfg.AzureCosmosDBConnectionString,
				Endpoint:                 cfg.AzureCosmosDBEndpoint,
				Obsv:                     obsv,
				AzureCosmosDBSPNTenantID: cfg.AzureCosmosDBSPNTenantID,
				AzureCosmosDBSPNClientID: cfg.AzureCosmosDBSPNClientID,
			},
		})
		if err != nil {
			return nil, goerrors.Errorf("failed to create Cosmos memory store: %w", err)
		}
	}

	secretScanner := secretscanning.NewSecretScanner(cfg.TokenScanningURL, cfg.TokenScanningHMACKey)
	billingEntityResolver := newTwirpBillingEntityResolver(ghTwirp)
	return core.NewMemoryService(memoryStore, featureFlagClient, secretScanner, obsv, ghTwirp, billingEntityResolver), nil
}

type twirpBillingEntityResolver struct {
	client githubtwirp.ClientInterface
}

func newTwirpBillingEntityResolver(client githubtwirp.ClientInterface) core.BillingEntityResolver {
	if client == nil {
		return nil
	}
	return &twirpBillingEntityResolver{client: client}
}

func (r *twirpBillingEntityResolver) ResolveBillingEntity(ctx context.Context, userID int64) (core.BillingEntity, error) {
	be, err := githubtwirp.ResolveBillingEntity(ctx, r.client, userID)
	if err != nil {
		return core.BillingEntity{}, err
	}
	return core.BillingEntity{
		OrganizationID: be.OrganizationID,
		EnterpriseID:   be.EnterpriseID,
		Resolved:       be.Resolved,
	}, nil
}
