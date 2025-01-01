package mysql

import (
	"context"
	"sync"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/gormext"

	"github.com/stretchr/testify/require"
)

func TestNextNumberConcurrent(t *testing.T) {
	db := gormext.GetDB(dbtest.RequireConnectionWithoutAutoIncrement(t))

	ctx := context.Background()

	seq := &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    42,
		db:        db,
	}

	var seen sync.Map

	var wg sync.WaitGroup

	// start concurrently grabbing sequences across 10 goroutines
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()

			for j := 0; j < 10; j++ {
				n, err := seq.Incr(ctx, 2)
				require.NoError(t, err)
				// every number should be unique
				_, loaded := seen.LoadOrStore(n, true)
				require.False(t, loaded)
			}
		}()
	}

	wg.Wait()

	count := 0
	keys := make(map[uint32]struct{})

	seen.Range(func(key interface{}, value interface{}) bool {
		keys[key.(uint32)] = struct{}{}
		count += 1
		return true
	})

	// we should see 100 keys, starting from 1 and incrementing by 2 each time
	require.Equal(t, 100, count)

	for i := uint32(0); i < 100; i++ {
		require.Contains(t, keys, 1+i*2)
	}
}

func TestIncrFirstNumber(t *testing.T) {
	db := gormext.GetDB(dbtest.RequireConnectionWithoutAutoIncrement(t))

	var n uint32
	var err error
	ctx := context.Background()

	seq := &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    42,
		db:        db,
	}

	n, err = seq.Incr(ctx, 2)
	require.NoError(t, err)
	require.Equal(t, uint32(1), n)

	n, err = seq.Next(ctx)
	require.NoError(t, err)
	require.Equal(t, uint32(3), n)
}

func TestNextNumber(t *testing.T) {
	db := gormext.GetDB(dbtest.RequireConnectionWithoutAutoIncrement(t))

	var n uint32
	ctx := context.Background()

	seq := &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    42,
		db:        db,
	}
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(1), n)
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(2), n)
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(3), n)
	n, _ = seq.Incr(ctx, 6)
	require.Equal(t, uint32(4), n)

	seq = &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    43,
		db:        db,
	}
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(1), n)

	seq = &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    42,
		db:        db,
	}
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(10), n)
}

func TestNextWithInvalidSQL(t *testing.T) {
	db := gormext.GetDB(dbtest.RequireConnectionWithoutAutoIncrement(t))
	ctx := context.Background()

	seq := &MySQLSequence{
		tableName: "invalid",
		repoID:    42,
		db:        db,
	}
	_, err := seq.Next(ctx)

	require.Contains(t, err.Error(), ".invalid' doesn't exist")

	seq = &MySQLSequence{
		tableName: ts.LogicalAlertsSeqTableName,
		repoID:    42,
		db:        db,
	}
	_, err = seq.Next(ctx)
	require.NoError(t, err)

	seq.tableName = "invalid"
	_, err = seq.Next(ctx)
	require.Contains(t, err.Error(), ".invalid' doesn't exist")
}
