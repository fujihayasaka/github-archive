package githubtwirp

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
)

type authorResolver struct {
	obsv     observability.Exporters
	ghTwirp  ClientInterface
	ffClient featureflags.Client
	cache    map[uint64]string
}

func NewAuthorResolver(obsv observability.Exporters, ghTwirp ClientInterface, ffClient featureflags.Client) *authorResolver {
	return &authorResolver{
		obsv:     obsv,
		ghTwirp:  ghTwirp,
		ffClient: ffClient,
		cache:    make(map[uint64]string),
	}
}

func (ar *authorResolver) Resolve(ctx context.Context, userID uint64, login string) (string, error) {
	if name, ok := ar.cache[userID]; ok {
		return name, nil
	}

	name, err := ResolveDisplayLogin(ctx, ar.ghTwirp, ar.obsv, ar.ffClient, userID, login)
	if err != nil {
		return "", err
	}
	ar.cache[userID] = name

	return name, nil
}
