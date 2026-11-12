// Package redis provides a simple way to construct a Redis client and a cache store implementation.
package redis

import (
	"context"
	"crypto/tls"
	"errors"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	gologger "github.com/github/github-telemetry-go/log"
	"github.com/github/go-redis/redislogging"
	"github.com/github/go-redis/redismetrics"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/redis/go-redis/v9"
)

// Based on https://github.com/github/copilot-api/blob/main/pkg/redis/redis.go

// RedisPeriodicPingInterval is the interval at which we ping Redis to keep the connection alive.
var RedisPeriodicPingInterval = 5 * time.Minute

// CustomTagsFn is a redismetrics.CustomTagsFn that is used to add additional tags to redis metrics.
var CustomTagsFn = redismetrics.CustomTagsFn(func(ctx context.Context, err error) stats.Tags {
	stats, _, _ := requestctx.ToTelemetry(ctx, nil)
	return stats
})

// NewClient creates a new Redis client with the given parameters.
func NewClient(ctx context.Context, redisConfig *config.RedisConfig, obsv observability.Exporters) (redis.UniversalClient, error) {
	// Construct the new client.
	client, err := newClient(redisConfig)
	if err != nil {
		return nil, err
	}

	// Ensure that we can connect to Redis, i.e. Ping it.
	err = runPing(ctx, client)
	if err != nil {
		return nil, err
	}

	logger := obsv.LoggerWithTelemetry(ctx).Named("redis")
	err = redislogging.StartRedisLoggingWithDefaultLogging(ctx, client, logger)
	if err != nil {
		return nil, err
	}

	err = redismetrics.StartRedisMetricsWithCustomTagsFn(ctx, client, obsv.Statter, logger, CustomTagsFn)
	if err != nil {
		return nil, err
	}

	// Redis connections are terminated if they are idle for 570 seconds.
	// This background job periodically pings Redis to keep some connection alive.
	schedulePeriodicPings(ctx, client, logger)

	return client, nil
}

func newClient(redisConfig *config.RedisConfig) (redis.UniversalClient, error) {
	if len(redisConfig.Hosts) > 0 {
		o := &redis.ClusterOptions{
			Addrs:       redisConfig.Hosts,
			Username:    redisConfig.Username,
			Password:    redisConfig.Password,
			PoolTimeout: 5 * time.Second,
			DialTimeout: 5 * time.Second,
			PoolSize:    redisConfig.PoolSize,
			// Set MaxActiveConns to the same value as pool size to avoid creating ephemeral connections in excess of the
			// pool size.
			MaxActiveConns: redisConfig.PoolSize,
			MinIdleConns:   redisConfig.MinIdleConns,
			// Despite the docs saying this helps to close idle connections faster,
			// this seems to actually keep connections open longer, which is what we
			// want.  It's magic, don't ask.
			PoolFIFO: true,
			// This value must be less than the Azure Redis Connection Idle Timeout (10 minutes or 600 seconds)
			// Azure Redis will terminate idle connections after this period of time, so the client needs to
			// remove connections that have idled for this amount of time from the pool
			ConnMaxIdleTime: time.Second * 570,
		}

		if redisConfig.TLSEnabled {
			if redisConfig.Servername == "" {
				return nil, errors.New("servername is required when enabling TLS")
			}

			o.TLSConfig = &tls.Config{
				MinVersion: tls.VersionTLS12,
				ServerName: redisConfig.Servername,
			}
		}

		return redis.NewClusterClient(o), nil
	}

	o := &redis.Options{
		Addr:        redisConfig.Host,
		Username:    redisConfig.Username,
		Password:    redisConfig.Password,
		DB:          redisConfig.DB,
		PoolTimeout: 5 * time.Second,
		DialTimeout: 5 * time.Second,
		PoolSize:    redisConfig.PoolSize,
		// Set MaxActiveConns to the same value as pool size to avoid creating ephemeral connections in excess of the
		// pool size.
		MaxActiveConns: redisConfig.PoolSize,
		MinIdleConns:   redisConfig.MinIdleConns,
		// Despite the docs saying this helps to close idle connections faster,
		// this seems to actually keep connections open longer, which is what we
		// want.  It's magic, don't ask.
		PoolFIFO: true,
		// This value must be less than the Azure Redis Connection Idle Timeout (10 minutes or 600 seconds)
		// Azure Redis will terminate idle connections after this period of time, so the client needs to
		// remove connections that have idled for this amount of time from the pool
		ConnMaxIdleTime: time.Second * 570,
	}

	if redisConfig.TLSEnabled {
		if redisConfig.Servername == "" {
			return nil, errors.New("servername is required when enabling TLS")
		}

		o.TLSConfig = &tls.Config{
			MinVersion: tls.VersionTLS12,
			ServerName: redisConfig.Servername,
		}
	}

	return redis.NewClient(o), nil
}

func runPing(ctx context.Context, c redis.UniversalClient) error {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()

	// Attempt to ping the Redis server with a 1s timeout to ensure
	// that we can connect to it.
	_, err := c.Ping(ctx).Result()
	if err != nil {
		// Not much we can do if this errors.
		_ = c.Close()
		return err
	}

	return nil
}

func schedulePeriodicPings(ctx context.Context, client redis.UniversalClient, logger gologger.Logger) {
	logger.Info(
		"Scheduling periodic Redis pings",
		kvp.String("gh.copilot_api.redis.ping_interval", RedisPeriodicPingInterval.String()),
	)

	go func() {
		t := time.NewTicker(RedisPeriodicPingInterval)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				_, err := client.Ping(ctx).Result()
				if err != nil {
					logger.WithError(err).Info("Error pinging redis")
				}
			case <-ctx.Done():
				logger.Info("Stopping periodic Redis pings, context is done")
				return
			}
		}
	}()
}
