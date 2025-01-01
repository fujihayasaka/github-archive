package mysql_dual_test

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/stretchr/testify/require"
)

func TestConnect(t *testing.T) {
	primaryConfig := dbtest.Config()
	replicaConfig := dbtest.Config()
	replicaConfig.ClientFoundRows = false
	c, err := mysql_dual.NewConnection(primaryConfig, replicaConfig)
	require.NoError(t, err)
	{
		_, err := c.Primary.ExecContext(context.Background(), "SELECT 1")
		require.NoError(t, err)
	}
	{
		row := c.Replica.QueryRowContext(context.Background(), "SELECT 1")
		require.NoError(t, row.Err())
	}
	require.NoError(t, c.Close())
}

func TestConnectSame(t *testing.T) {
	c, err := mysql_dual.NewConnection(dbtest.Config(), nil)
	require.NoError(t, err)
	{
		_, err := c.Primary.ExecContext(context.Background(), "SELECT 1")
		require.NoError(t, err)
	}
	{
		row := c.Replica.QueryRowContext(context.Background(), "SELECT 1")
		require.NoError(t, row.Err())
	}
	// check that Close does not error
	require.NoError(t, c.Close())
}
