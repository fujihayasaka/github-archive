package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
	"gopkg.in/yaml.v2"
)

// Inspired heavily by https://github.com/github/authzd/blob/master/internal/db/config.go

type DatabaseConfig struct {
	ConnectionName  string
	MysqlConfig     *mysql.Config
	ConnMaxIdleTime time.Duration
	ConnMaxLifetime time.Duration
	MaxOpenConns    int
	MaxIdleConns    int
}

type yamlMySqlConfig struct {
	mycnf *mysql.Config
}

func (c *yamlMySqlConfig) UnmarshalYAML(unmarshal func(interface{}) error) error {
	c.mycnf = newMySQLConfig()
	return unmarshal(c.mycnf)
}

// newMySQLConfig creates a base mysql.Config with authnd's default values applied.
func newMySQLConfig() *mysql.Config {
	// Set defaults for the MySQL config
	mycnf := mysql.NewConfig()
	mycnf.ParseTime = true
	mycnf.Net = "tcp"
	mycnf.InterpolateParams = true
	mycnf.Collation = "utf8mb4_unicode_520_ci"
	mycnf.MultiStatements = true
	return mycnf
}

func getDevConfig() map[string]*mysql.Config {
	mysql1Cfg := getDevConfigForCluster("mysql1", "github_development")
	authndCfg := getDevConfigForCluster("authnd", "github_development_authnd")
	collabCfg := getDevConfigForCluster("collab", "github_development_collab")
	lodgeCfg := getDevConfigForCluster("lodge", "github_development_lodge")

	return map[string]*mysql.Config{
		schemas.Mysql1RO: mysql1Cfg,
		schemas.AuthndRO: authndCfg,
		schemas.AuthndRW: authndCfg,
		schemas.CollabRO: collabCfg,
		schemas.CollabRW: collabCfg,
		schemas.LodgeRO:  lodgeCfg,
		schemas.LodgeRW:  lodgeCfg,
	}
}

func getDevConfigForCluster(name, defaultSchema string) *mysql.Config {
	cfg := newMySQLConfig()
	cfg.User = "root"

	cfg.Addr = os.Getenv("DB_ADDR")
	if cfg.Addr == "" {
		if os.Getenv("CODESPACES") == "true" {
			cfg.Addr = "localhost:3306"
		} else {
			cfg.Addr = "localhost:3001"
		}
	}
	if name == "mysql1" {
		cfg.DBName = os.Getenv("GITHUB_DATABASE")
	} else {
		envName := strings.ToUpper(name) + "_DATABASE"
		cfg.DBName = os.Getenv(envName)
	}
	if cfg.DBName == "" {
		cfg.DBName = defaultSchema
	}
	return cfg
}

func getTestSQLConfig() map[string]*mysql.Config {
	mysql1Cfg := getTestSQLConfigForCluster("mysql1", "github_test")
	authndCfg := getTestSQLConfigForCluster("authnd", "github_test_authnd")
	collabCfg := getTestSQLConfigForCluster("collab", "github_test_collab")
	lodgeCfg := getTestSQLConfigForCluster("lodge", "github_test_lodge")

	return map[string]*mysql.Config{
		schemas.Mysql1RO: mysql1Cfg,
		schemas.AuthndRO: authndCfg,
		schemas.AuthndRW: authndCfg,
		schemas.CollabRO: collabCfg,
		schemas.CollabRW: collabCfg,
		schemas.LodgeRO:  lodgeCfg,
		schemas.LodgeRW:  lodgeCfg,
	}
}

func getTestSQLConfigForCluster(name, defaultSchema string) *mysql.Config {
	cfg := newMySQLConfig()
	cfg.User = "root"
	cfg.Addr = "127.0.0.1:3306"

	cfg.DBName = defaultSchema
	if name == "mysql1" {
		cfg.Params = map[string]string{
			"transaction_isolation": "\"READ-UNCOMMITTED\"",
		}
	}
	return cfg
}

func TestDBConfig(dbName string) *DatabaseConfig {
	mysqlCfg := newMySQLConfig()
	mysqlCfg.DBName = dbName
	mysqlCfg.User = "root"

	mysqlCfg.Addr = os.Getenv("DB_ADDR")
	if mysqlCfg.Addr == "" {
		if os.Getenv("CODESPACES") == "true" {
			mysqlCfg.Addr = "localhost:3306"
		} else {
			mysqlCfg.Addr = "localhost:3001"
		}
	}

	return &DatabaseConfig{
		ConnectionName: dbName,
		MysqlConfig:    mysqlCfg,
		MaxOpenConns:   50,
		MaxIdleConns:   20,
	}
}

func (cfg *CommonConfig) MySQLClusterName() string {
	return fmt.Sprintf("authnd-%s", cfg.DeploymentEnvironment)
}

func (cfg *CommonConfig) DatabaseConfigFor(connection string) (*DatabaseConfig, error) {
	dbs, err := cfg.getDbConfig()
	if err != nil {
		return nil, err
	}

	if v, ok := dbs[connection]; ok {
		maxIdleTime, err := time.ParseDuration(cfg.MysqlConnMaxIdleTime)
		if err != nil {
			return nil, errors.Wrapf(err, "'%s' is not a valid time.Duration", cfg.MysqlConnMaxLifetime)
		}
		maxLifetime, err := time.ParseDuration(cfg.MysqlConnMaxLifetime)
		if err != nil {
			return nil, errors.Wrapf(err, "'%s' is not a valid time.Duration", cfg.MysqlConnMaxLifetime)
		}
		return &DatabaseConfig{
			MysqlConfig:     v,
			ConnectionName:  connection,
			ConnMaxIdleTime: maxIdleTime,
			ConnMaxLifetime: maxLifetime,
			MaxOpenConns:    cfg.MysqlMaxOpenConns,
			MaxIdleConns:    cfg.MysqlMaxIdleConns,
		}, nil
	}
	return nil, errors.Errorf("no known connection '%s'", connection)
}

func (cfg *CommonConfig) getDbConfig() (map[string]*mysql.Config, error) {
	// Initialize the config or error once.
	cfg.dbConfig.once.Do(func() {
		c, err := cfg.loadDBConfig()
		if err != nil {
			cfg.dbConfig.err = err
		} else {
			cfg.dbConfig.config = c
		}
	})

	if cfg.dbConfig.err != nil {
		return nil, cfg.dbConfig.err
	} else {
		return cfg.dbConfig.config, nil
	}
}

func (cfg *CommonConfig) loadDBConfig() (map[string]*mysql.Config, error) {
	if cfg.IsDevelopment() {
		return getDevConfig(), nil
	}

	if cfg.IsTest() && !cfg.IsDotcomCI() {
		return getTestSQLConfig(), nil
	}

	yamlPath := cfg.DatabaseConfigPath
	if yamlPath == "" {
		return nil, errors.New("missing db config file path")
	}

	buf, err := os.ReadFile(yamlPath)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	deployEnvironment := cfg.DeploymentEnvironment
	if cfg.IsEnterpriseServer {
		deployEnvironment = "enterprise"
	}
	if cfg.IsProxima {
		deployEnvironment = "proxima"
	}

	return readDBConfig(buf, deployEnvironment)
}

func readDBConfig(content []byte, environment string) (map[string]*mysql.Config, error) {
	// Normalize environment.
	if environment == "production/canary" {
		environment = "production"
	}

	s := string(content)
	s, err := expandPlaceholder(s)
	if err != nil {
		return nil, err
	}

	var data map[string]map[string]*yamlMySqlConfig
	err = yaml.UnmarshalStrict([]byte(s), &data)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	envConfig := make(map[string]*mysql.Config)

	// If the environment is enterprise or proxima, copy the enterprise specific ones
	// else, copy over all the values in the 'all' environment, then the environment specific ones.
	switch environment {
	case "enterprise":
		copyMap(data["enterprise"], envConfig)
	case "proxima":
		copyMap(data["proxima"], envConfig)
	default:
		copyMap(data["all"], envConfig)
		copyMap(data[environment], envConfig)
	}

	return envConfig, nil
}

func copyMap(src map[string]*yamlMySqlConfig, dest map[string]*mysql.Config) {
	if src == nil {
		return
	}

	for k, v := range src {
		dest[k] = v.mycnf
	}
}

func expandPlaceholder(s string) (string, error) {
	var err error
	value := os.Expand(s, func(key string) string {
		value, ok := os.LookupEnv(key)
		if !ok {
			err = errors.Errorf("missing %s in environment to replace placeholder", key)
		}
		return value
	})
	return value, err
}
