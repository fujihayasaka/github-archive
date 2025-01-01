package launchredis

import (
	"os"
	"testing"

	"github.com/redis/go-redis/v9"
)

type CloseFunc func()

func CreateRedisPoolConnectionForTest(t *testing.T) (redis.UniversalClient, CloseFunc, error) {
	t.Helper()

	url := os.Getenv("LAUNCH_REDIS_URL")
	if url == "" {
		url = "127.0.0.1:6379"
	}
	t.Logf("You can debug Redis keys by connecting with 'redis-cli' at this address: %s", url)

	opts := &redis.UniversalOptions{
		Addrs: []string{url},
	}

	client := redis.NewUniversalClient(opts)

	var closeFn CloseFunc = func() {
		client.Close()
	}

	return client, closeFn, nil
}
