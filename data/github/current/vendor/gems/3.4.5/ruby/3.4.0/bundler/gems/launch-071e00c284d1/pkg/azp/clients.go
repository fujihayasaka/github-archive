package azp

import (
	"context"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/abreaker"
)

// Clients encapsulate all AZP Clients we use.
type Clients struct {
	S2sClient      S2SClient
	KeyVaultClient KeyVaultClient

	RepositoryClientFactory RepositoryClientFactory
}

type Breakers struct {
	RepoBreaker     *circuit.Breaker
	TokenBreaker    *circuit.Breaker
	KeyVaultBreaker *circuit.Breaker
	S2SBreaker      *circuit.Breaker
}

func MakeBreakers(ctx context.Context, obs *observability.Observability, breakerConfig abreaker.Config) (*Breakers, error) {

	repoBreaker, err := abreaker.NewAzpRepoClientBreaker(ctx, obs, breakerConfig)
	if err != nil {
		return nil, err
	}

	tokenBreaker, err := abreaker.NewAzpBearerTokenBreaker(ctx, obs, breakerConfig)
	if err != nil {
		return nil, err
	}

	keyVaultBreaker, err := abreaker.NewAzpKeyVaultBreaker(ctx, obs, breakerConfig)
	if err != nil {
		return nil, err
	}

	s2sBreaker, err := abreaker.NewAzpS2SBreaker(ctx, obs, breakerConfig)
	if err != nil {
		return nil, err

	}

	return &Breakers{
		RepoBreaker:     repoBreaker,
		TokenBreaker:    tokenBreaker,
		KeyVaultBreaker: keyVaultBreaker,
		S2SBreaker:      s2sBreaker,
	}, nil
}
