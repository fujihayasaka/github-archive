package rate

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/testutils"
)

func Test_ConfigSyncService(t *testing.T) {
	ctx := context.Background()

	client, cancel, err := launchredis.CreateRedisPoolConnectionForTest(t)
	if err != nil {
		t.Errorf("Could not open connection to Redis: %v", err)
	}
	defer cancel()

	breaker := testutils.NewNoopBreaker()

	srv := NewConfigSyncService(
		observability.NewTestObservability(),
		client,
		breaker,
	)

	key := uuid.NewString()

	val, err := srv.Get(ctx, key)
	if err != nil && err != redis.Nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if val {
		t.Fatalf("Unexpected default value: %v", val)
	}

	if err := srv.Set(ctx, key, true); err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	val, err = srv.Get(ctx, key)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if !val {
		t.Fatalf("Unexpected value after set: %v", val)
	}

	if err := srv.Clear(ctx, key); err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	val, err = srv.Get(ctx, key)
	if err != redis.Nil {
		t.Fatalf("Expected an ErrNil error, got: %v, %v", val, err)
	}
}
