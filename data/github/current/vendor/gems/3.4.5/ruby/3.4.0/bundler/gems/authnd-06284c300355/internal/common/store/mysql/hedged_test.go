package mysql

import (
	"context"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/mocks"
	"github.com/golang/mock/gomock"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testMinMillisecondsBetweenHedges = 10

type testHedgeManager struct{}

func (hm *testHedgeManager) GetWaitTime() time.Duration {
	return testMinMillisecondsBetweenHedges * time.Millisecond
}

func (hm *testHedgeManager) GetMaxNumberOfHedges() int {
	return maxHedges
}

func (hm *testHedgeManager) HandleOperationDuration(operationDuration time.Duration) {
	// noop
}

func TestHedged_NoHedge(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		ctrl := gomock.NewController(t)
		defer ctrl.Finish()
		// creates a statter mock with basic statter ops that we don't care about asserting against in these test cases
		mockStatter := mocks.NewStatsClient(ctrl)
		mockStatter.EXPECT().DistributionMs("hedging.wait_time", gomock.Any(), gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("hedging.request", gomock.Any(), gomock.Any()).Times(1)
		ctx = diagnostics.WithStatter(ctx, mockStatter)

		// delay the original query, but not quite long enough to trigger the hedge call
		delay_original_query_for := 1 * time.Millisecond

		// expect the one call for the original query
		rows := sqlmock.NewRows([]string{"id", "name"})
		rows.AddRow(1, "bob")
		rows.AddRow(2, "alice")
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillDelayFor(delay_original_query_for).WillReturnRows(rows)

		var models []dummyModel
		r := &hedgedExecutor{ex: baseExecutor{"mock", mockDB}, hm: &testHedgeManager{}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)

		require.Len(t, models, 2)
		assert.Equal(t, int64(1), models[0].ID)
		assert.Equal(t, "bob", models[0].Name, "bob")
		assert.Equal(t, int64(2), models[1].ID)
		assert.Equal(t, "alice", models[1].Name)
	})
}

func TestHedged_PrimaryWinsRace(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		ctrl := gomock.NewController(t)
		defer ctrl.Finish()
		// creates a statter mock with basic statter ops that we don't care about asserting against in these test cases
		mockStatter := mocks.NewStatsClient(ctrl)
		mockStatter.EXPECT().DistributionMs("hedging.wait_time", gomock.Any(), gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("hedging.request", gomock.Any(), gomock.Any()).Times(2)
		ctx = diagnostics.WithStatter(ctx, mockStatter)

		// delay the original query enough to trigger the hedge call
		delay_original_query_for := (testMinMillisecondsBetweenHedges + 1) * time.Millisecond
		// also delay the hedge query so that it simulates the original query winning the race
		delay_hedge_query_for := (testMinMillisecondsBetweenHedges * time.Millisecond)

		// expect the original call
		original_response_rows := sqlmock.NewRows([]string{"id", "name"})
		original_response_rows.AddRow(1, "bob")
		original_response_rows.AddRow(2, "alice")
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillDelayFor(delay_original_query_for).WillReturnRows(original_response_rows)

		// expect the query again from the hedge call
		// return empty response so we can assert that the original call wins and returns properly when there is a hedge in progress
		hedge_response_rows := sqlmock.NewRows([]string{"id", "name"})
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillDelayFor(delay_hedge_query_for).WillReturnRows(hedge_response_rows)

		var models []dummyModel
		r := &hedgedExecutor{ex: baseExecutor{"mock", mockDB}, hm: &testHedgeManager{}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)

		require.Len(t, models, 2)
		assert.Equal(t, int64(1), models[0].ID)
		assert.Equal(t, "bob", models[0].Name, "bob")
		assert.Equal(t, int64(2), models[1].ID)
		assert.Equal(t, "alice", models[1].Name)
	})
}

func TestHedged_HedgeWins(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		ctrl := gomock.NewController(t)
		defer ctrl.Finish()
		// creates a statter mock with basic statter ops that we don't care about asserting against in these test cases
		mockStatter := mocks.NewStatsClient(ctrl)
		// expect a stat that the hedging beat our original query
		mockStatter.EXPECT().DistributionMs("hedging.wait_time", gomock.Any(), gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("hedging.paid_off", gomock.Any(), gomock.Any()).Times(1)
		mockStatter.EXPECT().Counter("hedging.request", gomock.Any(), gomock.Any()).Times(2)
		ctx = diagnostics.WithStatter(ctx, mockStatter)

		// delay the original query enough to trigger the hedge call
		delay_original_query_for := 2 * testMinMillisecondsBetweenHedges * time.Millisecond

		// expect the original call
		// return empty response so we can assert that the hedge call wins and returns properly when there is a hedge in progress
		original_response_rows := sqlmock.NewRows([]string{"id", "name"})
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillDelayFor(delay_original_query_for).WillReturnRows(original_response_rows)

		// expect the query to be triggered by the hedge
		// return rows in hedge response to prove that the hedge response is used in favor of the original response since it wins the race
		hedge_response_rows := sqlmock.NewRows([]string{"id", "name"})
		hedge_response_rows.AddRow(1, "bob")
		hedge_response_rows.AddRow(2, "alice")
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnRows(hedge_response_rows)

		var models []dummyModel
		r := &hedgedExecutor{ex: baseExecutor{"mock", mockDB}, hm: &testHedgeManager{}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)

		require.Len(t, models, 2)
		assert.Equal(t, int64(1), models[0].ID)
		assert.Equal(t, "bob", models[0].Name, "bob")
		assert.Equal(t, int64(2), models[1].ID)
		assert.Equal(t, "alice", models[1].Name)
	})
}
