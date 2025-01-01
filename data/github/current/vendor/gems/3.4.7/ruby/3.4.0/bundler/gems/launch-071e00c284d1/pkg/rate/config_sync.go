package rate

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
)

type ConfigSyncService interface {
	Get(context.Context /** configName */, string) ( /** configValue */ bool, error)
	Set(context.Context /** configName */, string /** configValue */, bool) error
	Clear(context.Context /** configName */, string) error
}

func NewConfigSyncService(
	obs *observability.Observability,
	client redis.UniversalClient,
	breaker *circuit.Breaker) ConfigSyncService {
	return &configSyncService{
		obs:     obs,
		client:  client,
		breaker: breaker,
	}
}

type configSyncService struct {
	obs     *observability.Observability
	client  redis.UniversalClient
	breaker *circuit.Breaker
}

func (srv *configSyncService) Get(ctx context.Context, configKey string) ( /** configValue */ bool, error) {
	res := srv.client.Get(ctx, configKey)
	if res.Err() != nil {
		if res.Err() != context.Canceled {
			srv.breaker.Fail()
		}
		return false, res.Err()
	}
	return res.Bool()
}

func (srv *configSyncService) Set(ctx context.Context, configKey string, configValue bool) error {
	res := srv.client.Set(ctx, configKey, configValue, 30*24*time.Hour)
	if res.Err() != nil {
		if res.Err() != context.Canceled {
			srv.breaker.Fail()
		}
	}
	return res.Err()
}

func (srv *configSyncService) Clear(ctx context.Context, configName string) error {
	res := srv.client.Del(ctx, configName)
	if res.Err() != nil {
		srv.breaker.Fail()
	}
	return res.Err()
}
