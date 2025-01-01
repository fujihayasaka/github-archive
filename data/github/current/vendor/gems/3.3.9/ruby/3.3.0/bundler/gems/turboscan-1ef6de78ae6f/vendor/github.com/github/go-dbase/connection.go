// Package dbase provides a database helper to load Skeema configuration for services written in Go.
package dbase

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/go-sql-driver/mysql"
	"github.com/jinzhu/gorm"
	_ "github.com/jinzhu/gorm/dialects/mysql"
)

// Config creates a `mysql.Config` struct for the given database environment.
// Information about the MySQL connection is read from the skeema file; the
// skeema section name _must_ be used for the `database` param . If the given
// environment cannot be found, this function will error out.
// The password for the MySQL database will always be loaded from the environment
// variable "MYSQL_PASSWORD".
// Additional Skeema environments can be specified using the "DBASE_ADDITIONAL_ENV" environment variable
// which is a comma-separated string. This allows overrides to be supplied through the configuration.
// For example you may have both a [development] and a [docker] section in the .skeema file. The [docker] section
// could have settings that adjust for the docker network environment (for example host and port)
// By setting DBASE_ADDITIONAL_ENV=docker and passing "development" to Config, the config loader will use both sections -- with any settings
// found in [docker] taking precedence over [development] (in other words: overriding [development]).
func Config(configFile string, environments ...string) (*mysql.Config, error) {
	file := NewFile(configFile)
	if err := file.Parse(); err != nil {
		return nil, err
	}

	if len(environments) == 0 {
		environments = []string{"development"}
	}

	// Check if any additional Skeema environments are specified by the environment variable
	// If so, include those sections in the configuration loader
	additionalEnv := os.Getenv("DBASE_ADDITIONAL_ENV")
	if additionalEnv != "" {
		envs := strings.Split(additionalEnv, ",")
		environments = append(environments, envs...)
	}

	// Reverse the slice to get the correct precedence order
	sort.Sort(sort.Reverse(sort.StringSlice(environments)))

	if err := file.UseSection(environments...); err != nil {
		return nil, err
	}

	var missing []string
	cfgvar := func(key string) string {
		val, ok := file.OptionValue(key)
		if !ok {
			missing = append(missing, fmt.Sprintf("(%s).%s", strings.Join(environments, ","), key))
			return ""
		}
		return val
	}

	config := mysql.NewConfig()
	config.User = cfgvar("user")
	config.Passwd = os.Getenv("MYSQL_PASSWORD") // returns "" if not set
	config.DBName = cfgvar("schema")
	config.Addr = fmt.Sprintf("%s:%s", cfgvar("host"), cfgvar("port"))
	config.Net = "tcp"
	if tls := os.Getenv("MYSQL_TLS"); tls != "" {
		config.TLSConfig = tls
	}
	config.ParseTime = true
	config.Params = map[string]string{
		"charset": file.OptionValueWithDefault("default-character-set", "utf8mb4"),
	}

	if len(missing) != 0 {
		return nil, fmt.Errorf("missing values in config file '%s': %s",
			configFile, strings.Join(missing, ", "))
	}
	return config, nil
}

// Open creates a new database connection using the `gorm` ORM.
func Open(skeema, environment string) (*gorm.DB, error) {
	config, err := Config(skeema, environment)
	if err != nil {
		return nil, err
	}

	dsn := config.FormatDSN()
	db, err := gorm.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize DB connection for %q, got: %w", dsn, err)
	}

	db.LogMode(false)
	return db, nil
}

// DBServerOpen connects to the server with no database selected. Necessary when droping the
// database and waiting for the server to become available.
func DBServerOpen(skeema, environment string) (*gorm.DB, error) {
	config, err := Config(skeema, environment)
	if err != nil {
		return nil, err
	}
	// Reset DBName; we don't want to connect to a named DB
	config.DBName = ""
	return gorm.Open("mysql", config.FormatDSN())
}
