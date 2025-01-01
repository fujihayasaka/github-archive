package mysql

import (
	"context"
	"database/sql"
	"testing"
	"time"

	freno "github.com/github/go-freno-client"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_gcRepositories(t *testing.T) {
	conn := testDB(t)

	q := `
INSERT INTO
  blackbird_epochs (id, corpus_id, description, created_at, updated_at)
VALUES
  (1, 0, 'an epoch', UTC_TIMESTAMP()-INTERVAL 25 HOUR, UTC_TIMESTAMP())
`
	_, err := conn.Exec(q)
	require.NoError(t, err)

	repos := []*db.Repository{
		// old enough to be deleted
		{
			RepoID:     1,
			OwnerID:    1,
			OwnerLogin: "nova-labs",
			Name:       "saint",
			DeletedAt:  sql.NullTime{Time: time.Now().Add(-24 * 7 * time.Hour).Add(-3 * time.Second), Valid: true},
		},
		// not old enough to be deleted
		{
			RepoID:     2,
			OwnerID:    1,
			OwnerLogin: "hal",
			Name:       "9000",
			DeletedAt:  sql.NullTime{Time: time.Now().Add(-24 * 6 * time.Hour).Add(3 * time.Second), Valid: true},
		},
	}

	helpers.InsertRepositories(t, conn, repos...)

	maint := &Maint{db: conn, throttler: freno.DefaultThrottler}
	err = maint.GC(context.Background())
	require.NoError(t, err)

	ids := []uint32{}
	err = conn.Select(&ids, "SELECT id FROM blackbird_repositories")
	require.NoError(t, err)
	require.ElementsMatch(t, []uint32{2}, ids)
}
