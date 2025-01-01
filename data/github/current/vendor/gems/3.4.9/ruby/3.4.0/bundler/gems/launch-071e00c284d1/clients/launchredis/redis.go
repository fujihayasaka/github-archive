package launchredis

import (
	"context"
	"crypto/tls"
	"time"

	"github.com/github/go-redis/redislogging"
	"github.com/github/go-redis/redismetrics"
	"github.com/redis/go-redis/v9"

	"github.com/github/launch/observability"
)

type RedisConfig struct {
	RedisUsername           string        `config:"launch,env=LAUNCH_REDIS_USERNAME"`
	RedisSecret             string        `config:",env=LAUNCH_REDIS_SECRET"`
	RedisURL                string        `config:",env=LAUNCH_REDIS_URL"`
	RedisUseTLS             bool          `config:"false,env=LAUNCH_REDIS_USE_TLS"`
	RedisMaxIdleConnections int           `config:"100,env=LAUNCH_REDIS_MAX_IDLE_CONNECTIONS"`
	RedisIdleTimeout        time.Duration `config:"30s,env=LAUNCH_REDIS_IDLE_CONNECTION_TIMEOUT"`
}

func New(ctx context.Context, cfg RedisConfig, obs *observability.Observability) (redis.UniversalClient, error) {
	opts := &redis.UniversalOptions{
		Addrs:    []string{cfg.RedisURL},
		Username: cfg.RedisUsername,
		Password: cfg.RedisSecret,

		DialTimeout: 30 * time.Second,

		ConnMaxIdleTime: cfg.RedisIdleTimeout,
		MaxIdleConns:    cfg.RedisMaxIdleConnections,

		MaxRetries:      3,
		MinRetryBackoff: 1 * time.Second,
		MaxRetryBackoff: 30 * time.Second,
	}
	if cfg.RedisUseTLS {
		opts.TLSConfig = &tls.Config{}
	}
	client := redis.NewUniversalClient(opts)
	if err := redismetrics.StartRedisMetrics(ctx, client, obs.Statter.Client(), obs.Logger.ToOtelLogger()); err != nil {
		return nil, err
	}
	if err := redislogging.StartRedisLoggingWithDefaultLogging(ctx, client, obs.Logger.ToOtelLogger()); err != nil {
		return nil, err
	}
	return client, nil
}
