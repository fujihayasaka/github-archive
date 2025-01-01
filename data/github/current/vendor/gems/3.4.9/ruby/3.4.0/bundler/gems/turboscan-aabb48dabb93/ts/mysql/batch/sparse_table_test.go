package batch

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
)

func TestSparseTable(t *testing.T) {
	db := dbtest.RequireConnection(t)

	now := time.Now()

	var repos []*ts.Repository

	for i := 1; i <= 5; i++ {
		repo := &ts.Repository{
			RepositoryID:    ts.RepositoryEID(i * 10_000),
			DefaultRef:      []byte("main"),
			SourceUpdatedAt: sqltime.Time{Time: now},
			BaseModel: ts.BaseModel{
				CreatedAt: sqltime.Time{Time: now},
			},
		}
		dbtest.RequireCreate(t, db, repo)

		repos = append(repos, repo)
	}

	var calls [][]uint64
	err := SparseTable(context.Background(), db, "ts_repositories", "repository_id", 2, func(ctx context.Context, db *gorm.DB, start, end uint64) error {
		calls = append(calls, []uint64{start, end})

		return nil
	})
	require.NoError(t, err)
	require.Equal(t, [][]uint64{
		{uint64(1), uint64(repos[1].RepositoryID)},
		{uint64(repos[1].RepositoryID) + 1, uint64(repos[3].RepositoryID)},
		{uint64(repos[3].RepositoryID) + 1, uint64(repos[4].RepositoryID)},
	}, calls)
}
