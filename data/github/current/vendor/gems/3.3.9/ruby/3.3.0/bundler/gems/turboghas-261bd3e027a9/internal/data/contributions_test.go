package data_test

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/stretchr/testify/require"
)

func TestUpsertContribution(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	var found data.UpsertContributionArgs
	today := sqltime.Time{Time: time.Now().UTC().Truncate(24 * time.Hour)}
	yesterday := sqltime.Time{Time: time.Now().UTC().Truncate(24 * time.Hour).Add(-24 * time.Hour)}

	for _, args := range []struct {
		value    data.UpsertContributionArgs
		expected data.UpsertContributionArgs
		statter  func(t *testing.T, table string) stats.Client
	}{
		{
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
			},
			statter: expectInsert,
		},
		{
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test2@example.com"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test2@example.com"),
			},
			statter: expectUpdate,
		},
		{
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
			},
			statter: expectUpdate,
		},
		{
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
			},
			statter: expectMatch,
		},
	} {
		require.NoError(t, d.UpsertContribution(fromctx.Statter.With(ctx, args.statter(t, "tg_contributions")), args.value))
		require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_contributions")))
		require.NoError(t, db.QueryRow("SELECT repository_id, user_id, pushed_at, email FROM tg_contributions").Scan(
			&found.RepositoryID, &found.UserID, &found.PushedAt, &found.Email,
		))
		require.Equal(t, args.expected, found)
	}
}
