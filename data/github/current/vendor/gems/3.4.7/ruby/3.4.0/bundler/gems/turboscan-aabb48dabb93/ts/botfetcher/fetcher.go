// Package botfetcher contains the logic for fetching the Advanced Security bot's
// information.
// Once we can enforce this information to be present in all topologies (dotCom, Proxima, GHES)
// we can remove this package.
package botfetcher

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
)

// FromCfgOrAPI returns a function that returns the bot actor
// we will try to read it from the config, but if it is not set, we will
// fallback to reading it from the API.
func FromCfgOrAPI(cfg *config.Config, api CodeScanningBotInfoer) func(ctx context.Context) (*ts.ActorGRIDLogin, error) {
	actor := cfg.BotActor()
	if actor != nil {
		return Static(*actor)
	}
	return cachedAPI(api)
}

func Static(a ts.ActorGRIDLogin) func(ctx context.Context) (*ts.ActorGRIDLogin, error) {
	return func(ctx context.Context) (*ts.ActorGRIDLogin, error) {
		return &a, nil
	}
}

type CodeScanningBotInfoer interface {
	GetCodeScanningBotInfo(ctx context.Context) (*ts.ActorGRIDLogin, error)
}

func cachedAPI(api CodeScanningBotInfoer) func(ctx context.Context) (*ts.ActorGRIDLogin, error) {
	var cached *ts.ActorGRIDLogin
	return func(ctx context.Context) (*ts.ActorGRIDLogin, error) {
		if cached != nil {
			return cached, nil
		}
		var err error
		cached, err = api.GetCodeScanningBotInfo(ctx)
		if err != nil {
			cached = nil
		}
		return cached, err
	}
}
