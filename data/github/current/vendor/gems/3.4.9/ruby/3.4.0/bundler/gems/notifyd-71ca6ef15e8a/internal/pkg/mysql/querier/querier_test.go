package querier

import (
	"context"
	"crypto/rand"
	"database/sql"
	"fmt"
	"testing"

	"github.com/Masterminds/squirrel"
	ghconfig "github.com/github/go-config"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/mysql"
)

func Test_base_Insert(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, table := prepareDB(ctx, t, 1)

	query := squirrel.Insert(table).Columns("name").Values("row1").Values("row2").Values("row3")
	querier := base{}
	result, err := querier.Insert(ctx, db, query)
	r.NoError(err)

	ids := make(map[int64]int64)
	err = result.EachID(func(idx, id int64) { ids[idx] = id }, 1)
	r.NoError(err)

	// It is safe to assume ids will be 1, 2 and 3 because it is a new table on each test.
	r.Equal(map[int64]int64{0: 1, 1: 2, 2: 3}, ids)
}

func Test_base_Insert_Custom_auto_increment(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	autoIncrement := 10000
	db, table := prepareDB(ctx, t, int64(autoIncrement))

	query := squirrel.Insert(table).Columns("name").Values("row1").Values("row2").Values("row3")
	querier := base{}
	result, err := querier.Insert(ctx, db, query)
	r.NoError(err)

	ids := make(map[int64]int64)
	err = result.EachID(func(idx, id int64) { ids[idx] = id }, int64(autoIncrement))
	r.NoError(err)

	// It is safe to assume ids will be 1, 2 and 3 because it is a new table on each test.
	r.Equal(map[int64]int64{0: 1, 1: 10001, 2: 20001}, ids)
}

func Test_AutoIncrementStep(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, _ := prepareDB(ctx, t, 10000)
	querier := base{}

	txx, err := db.BeginTxx(ctx, &sql.TxOptions{})
	r.NoError(err)

	step, err := querier.AutoIncrementStep(ctx, txx)
	r.NoError(err)

	r.Equal(int64(10000), step)
}

type Config struct {
	Environment string `config:",env=APP_ENV"`
	Database    mysql.Config
}

func prepareDB(ctx context.Context, t *testing.T, autoIncrement int64) (*sqlx.DB, string) {
	t.Helper()
	r := require.New(t)

	config.LoadDotEnv()
	cfg := Config{Environment: "development"}
	err := ghconfig.Load(&cfg)
	r.NoError(err)

	db, dbCleanup, err := mysql.New(ctx, cfg.Database, cfg.Environment)
	r.NoError(err)

	bytes := make([]byte, 5)
	_, err = rand.Read(bytes)
	r.NoError(err)

	table := fmt.Sprintf("test_%x", bytes)
	t.Logf("using temporary table: %s", table)

	_, err = db.Write.ExecContext(ctx, fmt.Sprintf("SET SESSION auto_increment_increment=%d", autoIncrement))
	r.NoError(err)

	createTable := fmt.Sprintf("CREATE TABLE IF NOT EXISTS `%s` ("+
		"`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, "+
		"`name` varchar(100) NOT NULL, "+
		"PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4", table)
	_, err = db.Write.ExecContext(ctx, createTable)
	r.NoError(err)

	t.Cleanup(func() {
		_, err = db.Write.ExecContext(ctx, fmt.Sprintf("drop table %s", table))
		r.NoError(err)
		err = dbCleanup()
		r.NoError(err)
	})

	return db.Write, table
}
