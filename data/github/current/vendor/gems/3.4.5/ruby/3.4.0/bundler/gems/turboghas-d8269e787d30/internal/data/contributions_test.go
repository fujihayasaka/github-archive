package data_test

import (
	"testing"
	"time"

	"github.com/simon-engledew/sqlh"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/stretchr/testify/require"
)

func TestUpsertContribution(t *testing.T) {
	ctx := t.Context()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	var found data.UpsertContributionArgs
	today := sqltime.Time{Time: time.Now().UTC().Truncate(24 * time.Hour)}
	yesterday := sqltime.Time{Time: time.Now().UTC().Truncate(24 * time.Hour).Add(-24 * time.Hour)}

	for _, args := range []struct {
		name     string
		value    data.UpsertContributionArgs
		expected data.UpsertContributionArgs
		statter  func(t *testing.T, table string) stats.Client
	}{
		{
			name: "insert data",
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("245002705fc27ae3c0d24bdd5500092cadc4ae3e"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("245002705fc27ae3c0d24bdd5500092cadc4ae3e"),
			},
			statter: expectInsert,
		},
		{
			name: "update data from yesterday",
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test2@example.com"),
				Commit:       data.Commit("245002705fc27ae3c0d24bdd5500092cadc4ae3e"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test2@example.com"),
				Commit:       data.Commit("245002705fc27ae3c0d24bdd5500092cadc4ae3e"),
			},
			statter: expectUpdate,
		},
		{
			name: "update data from today",
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("4688fe499cfd443bd946d0f5988156a9b127ed0d"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("4688fe499cfd443bd946d0f5988156a9b127ed0d"),
			},
			statter: expectUpdate,
		},
		{
			name: "do not update with stale data",
			value: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     yesterday,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("391913bb4e536e8600d2bdc96c3de91bfb7f6f81"),
			},
			expected: data.UpsertContributionArgs{
				RepositoryID: 1,
				UserID:       1,
				PushedAt:     today,
				Email:        []byte("test@example.com"),
				Commit:       data.Commit("4688fe499cfd443bd946d0f5988156a9b127ed0d"),
			},
			statter: expectMatch,
		},
	} {
		t.Run(args.name, func(t *testing.T) {
			require.NoError(t, d.UpsertContribution(fromctx.Statter.With(ctx, args.statter(t, "tg_contributions")), args.value))
			require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_contributions")))
			require.NoError(t, db.QueryRow("SELECT repository_id, user_id, pushed_at, email, commit FROM tg_contributions").Scan(
				&found.RepositoryID, &found.UserID, &found.PushedAt, &found.Email, sqlh.Binary(&found.Commit),
			))
			require.Equal(t, args.expected, found)
		})
	}
}
