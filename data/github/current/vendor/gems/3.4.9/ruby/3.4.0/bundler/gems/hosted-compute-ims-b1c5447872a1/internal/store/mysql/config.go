package mysql

import (
	"fmt"
	"time"

	"github.com/github/go-config"

	"github.com/go-sql-driver/mysql"
)

type Config struct {
	DbWriteUser        string `config:"root,env=MYSQL_USER"`
	DbWritePassword    string `config:",env=MYSQL_PASSWORD"`
	DbReadonlyUser     string `config:"readonly,env=MYSQL_READ_ONLY_USER"`
	DbReadonlyPassword string `config:",env=MYSQL_READ_ONLY_PASSWORD"`

	HttpPort     string `config:"28142,env=MYSQL_PORT"`
	Host         string `config:"127.0.0.1,env=MYSQL_HOST"`
	DatabaseName string `config:"hosted_compute_ims_development,env=MYSQL_DATABASE_NAME"`
	// Connection pool recommended settings are documented here https://github.com/github/go/blob/main/docs/database_access.md#setting-connection-timeouts
	ConnectionMaxLifetime  time.Duration `config:"5m,env=MYSQL_MAX_LIFETIME"`
	MaxOpenConnections     int           `config:"20,env=MYSQL_MAX_OPEN_CONNS"`
	ConnectionsMaxIdleTime int           `config:"10,env=MYSQL_MAX_IDLE_CONNS"`
	DBStatsInterval        time.Duration `config:"5s,env=DB_STATS_INTERVAL"`
}

func (c *Config) Load() error {
	if err := config.Load(c); err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	return nil
}

func (c *Config) connectionURL(user string, password string) string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?transaction_isolation='READ-COMMITTED", user, password, c.Host, c.HttpPort, c.DatabaseName)
}

func (c Config) DatabaseWriteURL() (string, error) {
	return c.databaseURL(c.connectionURL(c.DbWriteUser, c.DbWritePassword))
}

func (c Config) DatabaseReadURL() (string, error) {
	return c.databaseURL(c.connectionURL(c.DbReadonlyUser, c.DbReadonlyPassword))
}

func (c Config) databaseURL(dsn string) (string, error) {
	cfg, err := mysql.ParseDSN(dsn)
	if err != nil {
		return "", err
	}

	cfg.ParseTime = true // parseTime=true allows us to scan MySQL datetime into time.Time
	cfg.InterpolateParams = true
	cfg.AllowNativePasswords = true
	cfg.MultiStatements = false
	cfg.Params = map[string]string{
		"charset":  "utf8mb4",
		"sql_mode": "STRICT_ALL_TABLES",
	}

	dsn = cfg.FormatDSN()

	return dsn, nil
}
