package schemas

import (
	_ "embed"
	"fmt"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	ini "gopkg.in/ini.v1"
)

// dotSkeema is the the contents of schemas/.skeema. This code is located where
// it is because Go embedded cannot go up directores.
//
//go:embed .skeema
var dotSkeema []byte

// Return an open database connection from the given Skeema environment and
// password (for no password, use "").
func DB(skeemaEnv string, password string) *sqlx.DB {
	file, err := ini.LoadSources(ini.LoadOptions{AllowBooleanKeys: true}, dotSkeema)
	if err != nil {
		panic(fmt.Sprintf("could not load .skeema file: %+v", err))
	}

	section, err := file.GetSection(skeemaEnv)
	if err != nil {
		panic(fmt.Sprintf("could not get %q section: %+v", skeemaEnv, err))
	}

	dbConfig := mysql.NewConfig()
	dbConfig.Passwd = password
	dbConfig.ParseTime = true
	dbConfig.InterpolateParams = true
	dbConfig.Net = "tcp"

	for _, key := range section.Keys() {
		switch key.Name() {
		case "schema":
			dbConfig.DBName = key.Value()
		case "host":
			portKey, err := section.GetKey("port")
			if err != nil {
				panic("no port key")
			}
			dbConfig.Addr = fmt.Sprintf("%s:%s", key.Value(), portKey.Value())
		case "user":
			dbConfig.User = key.Value()
		default:
			// skip other configuration
		}

	}

	// NOTE: sqlx.Connect also does a ping, so this does connect, unlike sql.Open.
	db, err := sqlx.Connect("mysql", dbConfig.FormatDSN())
	if err != nil {
		panic(err)
	}

	// Borrowed from https://github.com/go-sql-driver/mysql#usage -- we'll need to tweak these for production.
	// The order of `SetConnMaxIdleTime` and `SetConnMaxLifetime`matters. See https://github.com/golang/go/issues/45993.
	db.SetConnMaxIdleTime(time.Second * 25)
	db.SetConnMaxLifetime(time.Minute * 3)
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(10)

	var tz string
	if err := db.Get(&tz, "SELECT @@system_time_zone"); err != nil {
		panic("could not get system time zone")
	}

	if !(tz == "PDT" || tz == "PST") {
		panic(fmt.Sprintf("unexpected database time zone. Expected PDT, got %q", tz))
	}

	return db
}
