package config_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/config"
	"github.com/go-sql-driver/mysql"
)

func TestVitessShard(t *testing.T) {
	opt := config.VitessShard(0)
	{
		cfg := mysql.Config{}
		opt(&cfg)
		require.Equal(t, "", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development"}
		opt(&cfg)
		require.Equal(t, "turboscan_development", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_development:0@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development:1:1@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_development:1:0@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_develo\npment:1:1@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_develo\npment:1:0@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_:1development@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_:1development:0@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development:1@master@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_development:0@master@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development:1@master"}
		opt(&cfg)
		require.Equal(t, "turboscan_development:0@master", cfg.DBName)
	}
	{
		cfg := mysql.Config{DBName: "turboscan_development:1@replica"}
		opt(&cfg)
		require.Equal(t, "turboscan_development:0@replica", cfg.DBName)
	}
}
