package main

import (
	"context"
	"testing"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

type step struct {
	start, end uint64
}

func captureSteps(steps *[]step, failures int) func(ctx context.Context, start, end uint64) error {
	return func(ctx context.Context, start, end uint64) error {
		*steps = append(*steps, step{
			start: start,
			end:   end,
		})
		if failures > 0 {
			failures -= 1
			return errors.New("batch failure")
		}
		return nil
	}
}

type maxRetryContext struct {
	context.Context
}

var _ fromctx.BackOffOverride = maxRetryContext{}

func (maxRetryContext) BackOff() backoff.BackOff {
	return backoff.WithMaxRetries(backoff.NewConstantBackOff(0), 10)
}

func TestBatches(t *testing.T) {
	db := dbtest.RequireConnection(t)

	ctx := maxRetryContext{Context: t.Context()}

	require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1, func(ctx context.Context, start, end uint64) error {
		require.Fail(t, "should not call function as there is no data")
		return nil
	}))

	res, err := db.Exec(`INSERT INTO tg_users (created_at, updated_at, user_id, login, type) VALUES (NOW(), NOW(), ?, ?, ?)`, 1, "user-1", v1.UserType_USER_TYPE_USER)
	require.NoError(t, err)

	lastInsertID, err := res.LastInsertId()
	require.NoError(t, err)

	firstID := uint64(lastInsertID)

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1, captureSteps(&steps, 0)))
		require.Equal(t, []step{{firstID, firstID}}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1_000, captureSteps(&steps, 0)))
		require.Equal(t, []step{{firstID, firstID}}, steps)
	}

	_, err = db.Exec(`INSERT INTO tg_users (created_at, updated_at, user_id, login, type) VALUES (NOW(), NOW(), ?, ?, ?)`, 2, "user-2", v1.UserType_USER_TYPE_USER)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO tg_users (created_at, updated_at, user_id, login, type) VALUES (NOW(), NOW(), ?, ?, ?)`, 3, "user-3", v1.UserType_USER_TYPE_USER)
	require.NoError(t, err)

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1, captureSteps(&steps, 0)))
		require.Equal(t, []step{
			{firstID, firstID},
			{firstID + 1, firstID + 1},
			{firstID + 2, firstID + 2},
		}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 2, captureSteps(&steps, 0)))
		require.Equal(t, []step{
			{firstID, firstID + 1},
			{firstID + 2, firstID + 2},
		}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1000, captureSteps(&steps, 0)))
		require.Equal(t, []step{{firstID, firstID + 2}}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1000, captureSteps(&steps, 1)))
		require.Equal(t, []step{
			{firstID, firstID + 2},
			{firstID, firstID + 1},
			{firstID + 2, firstID + 2},
		}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 1, captureSteps(&steps, 1)))
		require.Equal(t, []step{
			{firstID, firstID},
			{firstID, firstID},
			{firstID + 1, firstID + 1},
			{firstID + 2, firstID + 2},
		}, steps)
	}

	{
		var steps []step
		require.NoError(t, retryInBatches(ctx, dbtest.Dual(db), "tg_users", 2, captureSteps(&steps, 3)))
		require.Equal(t, []step{
			{firstID, firstID + 1},
			{firstID, firstID},
			{firstID, firstID},
			{firstID, firstID},
			{firstID + 1, firstID + 2},
		}, steps)
	}
}
