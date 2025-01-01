package config

import (
	"os"
	"path"
	"runtime"
	"testing"

	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/go-sql-driver/mysql"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDBConfigFile_Production(t *testing.T) {
	testDBConfigFile(t, "production")
}

func TestDbConfigFile_Test(t *testing.T) {
	testDBConfigFile(t, "test")
}

func TestDBConfigFile_Canary(t *testing.T) {
	testDBConfigFile(t, "production/canary")
}

func TestDbConfigFile_Enterprise(t *testing.T) {
	os.Setenv("IS_ENTERPRISE_SERVER", "true")
	testDBConfigFile(t, "enterprise")
	os.Setenv("IS_ENTERPRISE_SERVER", "false") // tests run sequentially, need to reset env var to default after changing value
}

func TestDatabaseConfigFor_Production(t *testing.T) {
	cfg := getTestConfig(t, "production")
	assertConfigFor(t, cfg, schemas.Mysql1RO, "db-mysql-github-ro.service.github.net", "mysql1_authnd_ro_0", "mysql1:ro:password", "github_production")
}

func TestDatabaseConfigFor_Enterprise(t *testing.T) {
	os.Setenv("IS_ENTERPRISE_SERVER", "true")
	cfg := getTestConfig(t, "enterprise")
	assertConfigFor(t, cfg, schemas.Mysql1RO, "authnd:enterprise:mysql_address", "authnd:enterprise:mysql_user", "authnd:enterprise:mysql_password", "github_enterprise")
	os.Setenv("IS_ENTERPRISE_SERVER", "false") // tests run sequentially, need to reset env var to default after changing value
}

func TestDatabaseConfigFor_Development(t *testing.T) {
	cfg, err := NewCommonConfigFromEnvironment()
	require.NoError(t, err)

	localAddr := os.Getenv("DB_ADDR")
	if localAddr == "" {
		if os.Getenv("CODESPACES") == "true" {
			localAddr = "localhost:3306"
		} else {
			localAddr = "localhost:3001"
		}
	}

	assertConfigFor(t, cfg, schemas.AuthndRO, localAddr, "root", "", "github_development_authnd")
	assertConfigFor(t, cfg, schemas.AuthndRW, localAddr, "root", "", "github_development_authnd")
	assertConfigFor(t, cfg, schemas.Mysql1RO, localAddr, "root", "", "github_development")
}

func TestDatabaseConfigFor_Test(t *testing.T) {
	cfg := getTestConfig(t, "test")

	assertConfigFor(t, cfg, schemas.AuthndRO, "127.0.0.1:3306", "root", "", "github_test_authnd")
	assertConfigFor(t, cfg, schemas.AuthndRW, "127.0.0.1:3306", "root", "", "github_test_authnd")
	c := assertConfigFor(t, cfg, schemas.Mysql1RO, "127.0.0.1:3306", "root", "", "github_test")
	assert.Equal(t, "\"READ-UNCOMMITTED\"", c.MysqlConfig.Params["transaction_isolation"])
}

func getTestConfig(t *testing.T, environment string) *CommonConfig {
	var databasesFilePath string
	if environment == "enterprise" {
		databasesFilePath = path.Clean(path.Join(getMyDir(), "../../../config/databases-enterprise.yml"))
	} else if environment == "test" {
		databasesFilePath = path.Clean(path.Join(getMyDir(), "../../../config/databases-test.yml"))
	} else {
		databasesFilePath = path.Clean(path.Join(getMyDir(), "../../../config/databases.yml"))
	}

	require.FileExists(t, databasesFilePath)

	// Set test env vars
	os.Setenv("MYSQL_MYSQL1_RO_PASSWORD", "mysql1:ro:password")
	os.Setenv("MYSQL_AUTHND_RO_PASSWORD", "authnd:ro:password")
	os.Setenv("MYSQL_AUTHND_RW_PASSWORD", "authnd:rw:password")
	os.Setenv("MYSQL_AUTHND_RW_USER", "authnd:rw:user")
	os.Setenv("MYSQL_AUTHND_RO_USER", "authnd:ro:user")
	os.Setenv("MYSQL_COLLAB_RO_PASSWORD", "collab:ro:password")
	os.Setenv("MYSQL_COLLAB_RO_USER", "collab:ro:user")
	os.Setenv("MYSQL_LODGE_RO_PASSWORD", "lodge:ro:password")
	os.Setenv("MYSQL_LODGE_RO_USER", "lodge:ro:user")

	// Set enterprise envs
	os.Setenv("MYSQL_PASSWORD", "authnd:enterprise:mysql_password")
	os.Setenv("MYSQL_USER", "authnd:enterprise:mysql_user")
	os.Setenv("MYSQL_ADDRESS", "authnd:enterprise:mysql_address")

	// Load the file
	cfg, err := NewCommonConfigFromEnvironment()
	require.NoError(t, err)
	cfg.DatabaseConfigPath = databasesFilePath
	cfg.DeploymentEnvironment = environment
	return cfg
}

func testDBConfigFile(t *testing.T, environment string) {
	cfg := getTestConfig(t, environment)
	dbs, err := cfg.getDbConfig()
	require.NoError(t, err)

	if environment == "enterprise" {
		for _, connName := range []string{
			schemas.Mysql1RO,
			schemas.AuthndRO,
			schemas.AuthndRW,
			schemas.CollabRO,
			schemas.CollabRW,
			schemas.LodgeRO,
			schemas.LodgeRW,
		} {
			testDBConfig(t, dbs, connName,
				"authnd:enterprise:mysql_address",
				"authnd:enterprise:mysql_user",
				"authnd:enterprise:mysql_password",
				"github_enterprise",
			)
		}
	} else if environment == "test" {
		testDBConfig(t, dbs, schemas.AuthndRO,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_authnd",
		)
		testDBConfig(t, dbs, schemas.AuthndRW,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_authnd",
		)
		testDBConfig(t, dbs, schemas.Mysql1RO,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test",
		)
		testDBConfig(t, dbs, schemas.CollabRO,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_collab",
		)
		testDBConfig(t, dbs, schemas.CollabRW,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_collab",
		)
		testDBConfig(t, dbs, schemas.LodgeRO,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_lodge",
		)
		testDBConfig(t, dbs, schemas.LodgeRW,
			"127.0.0.1:3306",
			"root",
			"",
			"github_test_lodge",
		)
	} else {
		testDBConfig(t, dbs, schemas.Mysql1RO,
			"db-mysql-github-ro.service.github.net",
			"mysql1_authnd_ro_0",
			"mysql1:ro:password",
			"github_production",
		)

		testDBConfig(t, dbs, schemas.AuthndRO,
			"db-mysql-authnd-production-ro.service.github.net",
			"authnd:ro:user",
			"authnd:ro:password",
			"authnd_production",
		)

		testDBConfig(t, dbs, schemas.AuthndRW,
			"db-mysql-authnd-production-rw.service.github.net",
			"authnd:rw:user",
			"authnd:rw:password",
			"authnd_production",
		)

		testDBConfig(t, dbs, schemas.CollabRO,
			"db-mysql-collab-ro.service.github.net",
			"collab:ro:user",
			"collab:ro:password",
			"github_production",
		)
		testDBConfig(t, dbs, schemas.CollabRW,
			"db-mysql-collab-rw.service.github.net",
			"collab:ro:user",
			"collab:ro:password",
			"github_production",
		)
		testDBConfig(t, dbs, schemas.LodgeRO,
			"db-mysql-lodge-ro.service.github.net",
			"lodge:ro:user",
			"lodge:ro:password",
			"lodge",
		)

		testDBConfig(t, dbs, schemas.LodgeRW,
			"db-mysql-lodge-rw.service.github.net",
			"lodge:ro:user",
			"lodge:ro:password",
			"lodge",
		)
	}

	// Verify we covered all the connections
	require.Len(t, dbs, 0, "there were additional unexpected db connections!")
}

func testDBConfig(t *testing.T, dbs map[string]*mysql.Config, name, addr, user, pass, db string) {
	assert.Contains(t, dbs, name)

	config, ok := dbs[name]
	if !ok {
		return
	}

	delete(dbs, name)
	assert.Equal(t, addr, config.Addr)
	assert.Equal(t, user, config.User)
	assert.Equal(t, pass, config.Passwd)
	assert.Equal(t, db, config.DBName)
}

func getMyDir() string {
	_, filename, _, _ := runtime.Caller(0)
	return path.Dir(filename)
}

func assertConfigFor(t *testing.T, cfg *CommonConfig, connectionName, addr, user, passwd, dbname string) (config *DatabaseConfig) {
	c, err := cfg.DatabaseConfigFor(connectionName)

	// Use assert because we might be testing multiple configs and we don't want to end the test if one result returned an error
	assert.NoError(t, err)

	// Only assert contents if there was no error.
	// This way, when an error occurs we aren't also deluged by failures for each individual comparison.
	if err == nil {
		assert.Equal(t, addr, c.MysqlConfig.Addr)
		assert.Equal(t, user, c.MysqlConfig.User)
		assert.Equal(t, passwd, c.MysqlConfig.Passwd)
		assert.Equal(t, dbname, c.MysqlConfig.DBName)
		assert.True(t, c.MysqlConfig.ParseTime)
		assert.Equal(t, "tcp", c.MysqlConfig.Net)
	}

	return c
}
