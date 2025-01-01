package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/mocks"
	"github.com/github/go-stats"
	"github.com/golang/mock/gomock"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const query = "SELECT `id`, `name` FROM fake_table LIMIT 1337"

func sqlReturnsRows(mock sqlmock.Sqlmock) {
	rows := sqlmock.NewRows([]string{"id", "name"})
	rows.AddRow(1, "bob")
	rows.AddRow(2, "alice")
	mock.ExpectQuery(query).WillReturnRows(rows)
}

func expectRows(t *testing.T, models []dummyModel) {
	require.Len(t, models, 2)
	assert.Equal(t, int64(1), models[0].ID)
	assert.Equal(t, "bob", models[0].Name, "bob")
	assert.Equal(t, int64(2), models[1].ID)
	assert.Equal(t, "alice", models[1].Name)
}

func sqlReturnsError(mock sqlmock.Sqlmock, err error) {
	mock.ExpectQuery(query).WillReturnError(err)
}

func withPrimaryReadTestSetup(t *testing.T, clusterHealthy bool, frenoError error,
	fn func(ctx context.Context, ex Executor, replicaMock sqlmock.Sqlmock, primaryMock sqlmock.Sqlmock, statter *mocks.StatsClient)) {

	db.WithMockDB(t, func(replicaDB *sqlx.DB, replicaMock sqlmock.Sqlmock) {
		db.WithMockDB(t, func(primaryDB *sqlx.DB, primaryMock sqlmock.Sqlmock) {
			ctrl := gomock.NewController(t)
			defer ctrl.Finish()

			statter := mocks.NewStatsClient(ctrl)
			ctx := diagnostics.WithStatter(context.Background(), statter)

			replicaEx, primaryEx := &baseExecutor{"read", replicaDB}, &baseExecutor{"write", primaryDB}
			throttler := &testThrottler{
				CanWriteFn: func(ctx context.Context) (bool, error) {
					return clusterHealthy, frenoError
				},
			}

			ex := &primaryReadsExecutor{replica: replicaEx, primary: primaryEx, throttler: throttler}
			fn(ctx, ex, replicaMock, primaryMock, statter)
		})
	})
}

func TestPrimaryRead_PolicyFallback_HealthyCluster_Success(t *testing.T) {
	withPrimaryReadTestSetup(t, true, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "true"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsRows(replicaMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_PolicyFallback_HealthyCluster_NoFallbackError(t *testing.T) {
	withPrimaryReadTestSetup(t, true, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "true"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, sql.ErrNoRows)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.Error(t, err)
		assert.Equal(t, err, sql.ErrNoRows)
	})
}

func TestPrimaryRead_PolicyFallback_FrenoError_ReadFromFallback(t *testing.T) {
	withPrimaryReadTestSetup(t, false, errors.New("freno is down"), func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_error": "true"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, sql.ErrNoRows)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.Error(t, err)
		assert.Equal(t, err, sql.ErrNoRows)
	})
}

func TestPrimaryRead_PolicyFallback_UnhealthyCluster_Success(t *testing.T) {
	withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "false"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsRows(replicaMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_PolicyFallback_UnhealthyCluster_FallbackToPrimarySuccess(t *testing.T) {
	withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "false"}
		primaryTags := tags.Merge(stats.Tags{"role": "primary"})
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags.Merge(primaryTags), gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, sql.ErrNoRows)
		sqlReturnsRows(primaryMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_PolicyFallback_UnhealthyCluster_FallbackToPrimaryCustomErrorSuccess(t *testing.T) {
	withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		badThingError := errors.New("bad thing happened")
		ctx = ContextPrimaryReadsOnError(ctx, badThingError)

		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "false"}
		primaryTags := tags.Merge(stats.Tags{"role": "primary"})
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags.Merge(primaryTags), gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, badThingError)
		sqlReturnsRows(primaryMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_PolicyFallback_UnhealthyCluster_NoFallbackToPrimaryCustomErrorMismatch(t *testing.T) {
	withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		ctx = ContextPrimaryReadsOnError(ctx, sql.ErrNoRows, errors.New("bad thing happened"))

		tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "false"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, errors.New("a different bad thing happened"))

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.Error(t, err)
		assert.EqualError(t, err, "a different bad thing happened")
	})
}
func TestPrimaryRead_PolicyPrimaryReads_HealthyCluster_Success(t *testing.T) {
	withPrimaryReadTestSetup(t, true, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		ctx = ContextPrimaryReadFallbackOnLag(ctx)

		tags := stats.Tags{"policy": "read_from_primary", "role": "replica", "freno_ok": "true"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsRows(replicaMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_PolicyPrimaryReads_HealthyCluster_Error(t *testing.T) {
	withPrimaryReadTestSetup(t, true, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		ctx = ContextPrimaryReadFallbackOnLag(ctx)

		tags := stats.Tags{"policy": "read_from_primary", "role": "replica", "freno_ok": "true"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsError(replicaMock, errors.New("bad thing happened"))

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.Error(t, err)
		assert.EqualError(t, err, "bad thing happened")
	})
}

func TestPrimaryRead_PolicyPrimaryReads_UnhealthyCluster_ReadsFromPrimary(t *testing.T) {
	withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
		ctx = ContextPrimaryReadFallbackOnLag(ctx)

		tags := stats.Tags{"policy": "read_from_primary", "role": "primary", "freno_ok": "false"}
		mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

		sqlReturnsRows(primaryMock)

		var models []dummyModel
		err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)
		expectRows(t, models)
	})
}

func TestPrimaryRead_FallbackAlways_ReadsFromPrimary(t *testing.T) {
	for _, healthy := range []bool{true, false} {
		t.Run(fmt.Sprintf("healthy cluster %t", healthy), func(t *testing.T) {
			withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
				ctx = ContextPrimaryReadFallbackAlways(
					ContextPrimaryReadsOnError(ctx, sql.ErrNoRows),
				)

				sqlReturnsError(replicaMock, sql.ErrNoRows)

				tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "skipped"}
				primaryTag := stats.Tags{"role": "primary"}
				mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)
				mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags.Merge(primaryTag), gomock.Any()).Times(1)

				sqlReturnsRows(primaryMock)

				var models []dummyModel
				err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
				require.NoError(t, err)
				expectRows(t, models)
			})
		})
	}
}

func TestPrimaryRead_FallbackAlways_ReadsFromReplica(t *testing.T) {
	for _, healthy := range []bool{true, false} {
		t.Run(fmt.Sprintf("healthy cluster %t", healthy), func(t *testing.T) {
			withPrimaryReadTestSetup(t, false, nil, func(ctx context.Context, ex Executor, replicaMock, primaryMock sqlmock.Sqlmock, mockStatter *mocks.StatsClient) {
				ctx = ContextPrimaryReadFallbackAlways(
					ContextPrimaryReadsOnError(ctx, sql.ErrNoRows),
				)

				tags := stats.Tags{"policy": "fallback", "role": "replica", "freno_ok": "skipped"}
				mockStatter.EXPECT().Counter("mysql.primary_reads_executor.read", tags, gomock.Any()).Times(1)

				sqlReturnsRows(replicaMock)

				var models []dummyModel
				err := ex.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
				require.NoError(t, err)
				expectRows(t, models)
			})
		})
	}
}
