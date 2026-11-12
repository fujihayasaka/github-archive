package config

// NOTE: the Redis related configuration code references how copilot-api service does it
// https://github.com/github/copilot-api/blob/577546f006c0b90f9fc073b87c4dc5bb376339f9/cmd/http/config/config.go#L398

// RedisConfigSection holds the configuration for the Redis connection.
type RedisConfigSection struct {
	RedisProvider   string `config:",env=REDIS_PROVIDER"`
	RedisHost       string `config:",env=REDIS_HOST"`
	RedisDB         int    `config:"0,env=REDIS_DB"`
	RedisUsername   string `config:"default,env=REDIS_USERNAME"`
	RedisPassword   string `config:",env=REDIS_PASSWORD"`
	RedisServername string `config:",env=REDIS_SERVERNAME"`
	// RedisPoolSize is the maximum number of connections in the pool. When changing this value it is recommended to
	// do it gradually and monitor the client side and server side connection metrics.
	RedisPoolSize int `config:"10,env=REDIS_POOL_SIZE"`
	// RedisMinIdleConns is the minimum number of connections the pool tries to maintain, even when not in use. When
	// this is the same value as RedisPoolSize the pool is essentially static. A static pool can be useful to handle
	// large increases of traffic that are sensitive to the few ms of latency that it takes to create a new connection.
	// Though, if the connections are not utilized they will sit idle and will continually be closed and re-opened to
	// maintain that static pool size. Azure Redis is sensitive to a high rate of new connections so it is important
	// to make sure the connection pool is tuned to the environment. `production` might benefit from a static pool, but
	// `staging` might be better suited with a dynamic pool where the MinIdleConns is set to a lower value.
	RedisMinIdleConns int `config:"10,env=REDIS_MIN_IDLE_CONNS"`
}

// RedisConfig holds the important bits of data for connecting to
// a Redis server.
type RedisConfig struct {
	Provider     RedisProvider
	Host         string
	Hosts        []string
	Username     string
	Password     string
	DB           int
	Servername   string
	PoolSize     int
	MinIdleConns int
	TLSEnabled   bool
}

// RedisProvider is an enum for the different Redis providers we support.
type RedisProvider string

// The different Redis providers we support.
var (
	Azure  RedisProvider = "AZURE"
	GitHub RedisProvider = "GITHUB"
	Local  RedisProvider = "LOCAL"
)

// String returns a string representation of the RedisProvider.
func (r RedisProvider) String() string {
	return string(r)
}

// RedisConfiguration returns the appropriate RedisConfig for the current
// environment, based off of the environment variable `REDIS_PROVIDER`.
// If we don't know how to construct a particular client, returns nil.
func (cfg *Config) RedisConfiguration() *RedisConfig {
	switch cfg.RedisProvider {
	case Azure.String():
		return &RedisConfig{
			Provider:     Azure,
			Host:         cfg.RedisHost,
			Username:     cfg.RedisUsername,
			Password:     cfg.RedisPassword,
			DB:           cfg.RedisDB,
			Servername:   cfg.RedisServername,
			PoolSize:     cfg.RedisPoolSize,
			MinIdleConns: cfg.RedisMinIdleConns,
			TLSEnabled:   true,
		}
	case GitHub.String():
		return &RedisConfig{
			Provider:     GitHub,
			Host:         cfg.RedisHost,
			Username:     cfg.RedisUsername,
			Password:     cfg.RedisPassword,
			DB:           cfg.RedisDB,
			Servername:   cfg.RedisServername,
			PoolSize:     cfg.RedisPoolSize,
			MinIdleConns: cfg.RedisMinIdleConns,
			TLSEnabled:   false, // TLS is not required when sweagentd and Redis are colocated in the same data center.
		}
	case Local.String():
		return &RedisConfig{
			Provider:     Local,
			Host:         cfg.RedisHost,
			Username:     cfg.RedisUsername,
			Password:     cfg.RedisPassword,
			DB:           cfg.RedisDB,
			Servername:   cfg.RedisServername,
			PoolSize:     cfg.RedisPoolSize,
			MinIdleConns: cfg.RedisMinIdleConns,
			TLSEnabled:   false,
		}
	default:
		return nil
	}
}
