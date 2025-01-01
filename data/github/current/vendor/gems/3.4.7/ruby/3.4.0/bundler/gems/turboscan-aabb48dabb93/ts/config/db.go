package config

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-dbase"
	"github.com/github/go-http/middleware/requestid"

	"github.com/github/go-queryannotations"
	"github.com/github/go-queryannotations/annotation"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/errorredaction"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/go-sql-driver/mysql"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// DBOptions describes how we want to connect to the database.
type DBOptions struct {
	Params map[string]string
	Config *Config
	// Overrides Config.MySQLSkeemaPath if set
	SkeemaPath string
	// Overrides Config.Environment if set
	SkeemaEnvironment string
	MultiStatements   bool
	// Ignores env.MYSQL_* if set
	IgnoreEnv bool
	// Replica attempts to connect to a replica if possible
	Replica bool
}

// EffectiveSkeemaPath returns the effective Skeema path, preferring opts.SkeemaPath
// if it is given
func (opts *DBOptions) EffectiveSkeemaPath() string {
	if opts.SkeemaPath != "" {
		return opts.SkeemaPath
	}

	// For tests we search upwards for '.git' in order to locate it
	if opts.Config.MySQLSkeemaPath == "" {
		dir, err := os.Getwd()
		if err != nil {
			return ""
		}

		for {
			fs, err := os.Stat(filepath.Join(dir, ".git"))
			if err == nil && fs.IsDir() {
				return filepath.Join(dir, "schemas/.skeema")
			}

			if !os.IsNotExist(err) {
				return ""
			}

			newDir := filepath.Dir(dir)
			if dir == newDir {
				return ""
			}
			dir = newDir
		}

	}

	return opts.Config.MySQLSkeemaPath
}

// EffectiveSkeemaEnvironment returns the effective Skeema environment, preferring
// opts.SkeemaEnvironment if it is given
func (opts *DBOptions) EffectiveSkeemaEnvironment() string {
	if opts.SkeemaEnvironment != "" {
		return opts.SkeemaEnvironment
	}
	return opts.Config.Environment
}

// DBConfig returns the complete MySQL configuration for the given DBOptions.
// The Skeema file and environment referenced by the Config (possibly overridden
// by SkeemaPath and SkeemaEnvironment) is loaded. Any non-zero values in the
// Config.MySQL* fields are then applied as overrides.
func (opts *DBOptions) DBConfig() (*mysql.Config, error) {
	cfg := opts.Config

	dbConfig, err := dbase.Config(opts.EffectiveSkeemaPath(), opts.EffectiveSkeemaEnvironment())
	if err != nil {
		return nil, errors.Errorf("build DB config: %s", err)
	}
	dbConfig.ParseTime = true
	dbConfig.InterpolateParams = true // forces statements to be prepared client-side see https://github.com/github/database-infrastructure/issues/2260#issuecomment-538617856
	dbConfig.Collation = "utf8mb4_general_ci"
	dbConfig.MultiStatements = opts.MultiStatements
	dbConfig.CheckConnLiveness = true // turns on the TCP connection checking described in https://github.blog/2020-05-20-three-bugs-in-the-go-mysql-driver/

	if dbConfig.Params == nil {
		dbConfig.Params = make(map[string]string)
	}
	if opts.Params != nil {
		for k, v := range opts.Params {
			dbConfig.Params[k] = v
		}
	}

	if !opts.IgnoreEnv {
		// Override the skeema environment configuration with any specifically
		// provided values in the environment
		if cfg.MySQLDBName != "" {
			dbConfig.DBName = cfg.MySQLDBName
		}

		if cfg.MySQLUsername != "" {
			dbConfig.User = cfg.MySQLUsername
		}

		if cfg.MySQLAddr != "" {
			dbConfig.Addr = cfg.MySQLAddr
		}

		if cfg.MySQLPassword != "" {
			dbConfig.Passwd = cfg.MySQLPassword
		}

		dbConfig.TLSConfig = cfg.MySQLTLS
	}

	return dbConfig, nil
}

func init() {
	// this is in the init function so that it is applied to connections created by dbtest

	// For GHES, we named all our tables as `ts_*`. This enables the automapping
	// of structs to tables.
	gorm.DefaultTableNameHandler = func(db *gorm.DB, defaultTableName string) string {
		return "ts_" + defaultTableName
	}
}

func ConfigureGorm(db *gorm.DB) {
	// Without this option, any preloaded associations will be automatically saved
	// when a database row is updated. Gorm has no way of knowing if an entity is
	// dirty, so this autoupdating would be done unconditionally.
	db.InstantSet("gorm:association_autoupdate", false)

	// register error enrichment callback
	gormext.AddGormErrorCallback(db)

	// register tracing callbacks. Note this is needed because Gorm doesn't has
	// context.Context support. If we upgrade to Gorm v2 or swap the underlying
	// DB driver
	otelgorm.Initialize(db)
}

var ErrNoReplica = errors.New("no configuration for connecting to a replica")

type DBOption func(*mysql.Config)

var vitessPattern = regexp.MustCompile(`(?s)\A(?P<Schema>.+?)(?P<Shard>:\d+)?@(?P<Host>.+)\z`)

func VitessShard(shard int) DBOption {
	return func(c *mysql.Config) {
		matches := vitessPattern.FindStringSubmatch(c.DBName)
		if len(matches) > 0 {
			c.DBName = matches[vitessPattern.SubexpIndex("Schema")] + ":" + strconv.Itoa(shard) + "@" + matches[vitessPattern.SubexpIndex("Host")]
		}
	}
}

// OpenDB opens a MySQL database instance. Internally it wraps the
// database connector in one that emits statistics to Datadog.
// Pass in nil to disable this functionality.
func OpenDB(opts *DBOptions, logger log.Logger, st stats.Client, dbopts ...DBOption) (*gorm.DB, error) {
	dbConfig, err := opts.DBConfig() // Contain whether to do instrumentation?
	if err != nil {
		return nil, err
	}
	if st == nil {
		st = stats.NullStatter
	}

	for _, opt := range dbopts {
		opt(dbConfig)
	}

	// if the configuration asked for a replica + we are using Vitess then we can ask Vitess
	// for a connection, otherwise we would need to load different config.
	if opts.Replica {
		if strings.HasSuffix(dbConfig.DBName, "@master") {
			dbConfig.DBName = strings.TrimSuffix(dbConfig.DBName, "@master") + "@replica"
		} else {
			// TODO: possibly load replica configuration from Skeema or Env
			return nil, ErrNoReplica
		}
	}

	logger = logger.WithFields(kvp.String("gh.turboscan.db_schema", dbConfig.DBName))
	annotations := queryannotations.WithAnnotations(
		annotation.Application("turboscan"),
		annotation.DeployedTo(opts.Config.Environment),
		func(ctx context.Context) *annotation.Annotation {
			requestID := requestid.GetGitHubRequestID(ctx)
			if requestID == "" {
				return nil
			}
			return &annotation.Annotation{
				Key:   annotation.RequestIDKey,
				Value: requestID,
			}
		},
		func(ctx context.Context) *annotation.Annotation {
			jobID, ok := ctx.Value("gh.aqueduct.job.id").(string)
			if !ok {
				return nil
			}
			return &annotation.Annotation{
				Key:   annotation.JobIDKey,
				Value: jobID,
			}
		},
	)

	db, err := Open(dbConfig, logger, st, annotations)
	if err != nil {
		return nil, errors.Errorf("open DB connection: %s", err)
	}

	// Use a null logger while configuring callbacks as the output is unhelpful
	// and ugly.
	nullLogger := log.NewNullLogger()
	db.SetLogger(gormext.NewGormLogger(nullLogger))
	ConfigureGorm(db)

	conn := gormext.GetDB(db)

	conn.SetMaxIdleConns(10)
	conn.SetMaxOpenConns(25)
	// This value plus the max time of any transaction should be less
	// than the length of time that GLB allows us to keep a connection
	// open (currently 5 mins, https://github.com/github/glb/pull/2026)
	conn.SetConnMaxLifetime(4*time.Minute + 30*time.Second)

	db.LogMode(true)
	gormLogger := gormext.NewGormLogger(logger)
	// TODO(kevinsawicki): Hack to expose the original logger used here to the
	// twirp middleware that tracks DB queries via the logger.
	db.InstantSet("staffbarLogger", gormLogger)

	cfg := opts.Config
	if cfg.IsProdEnv() || cfg.IsDevelopmentEnv() {
		db.Callback().Query().Register("redaction_callback", errorredaction.DatabaseRedactionCallback)
		db.Callback().Create().Register("redaction_callback", errorredaction.DatabaseRedactionCallback)
		db.Callback().Update().Register("redaction_callback", errorredaction.DatabaseRedactionCallback)
		db.Callback().Delete().Register("redaction_callback", errorredaction.DatabaseRedactionCallback)
	}

	db.SetLogger(gormLogger)

	if err := mysql.SetLogger(&mysqlLogger{log: logger}); err != nil {
		return nil, errors.Wrap(err, "unable to set logger")
	}

	return db, nil
}

func DBWithReplicaConnection(opts *DBOptions, logger log.Logger, st stats.Client) (*gorm.DB, error) {
	db, err := OpenDB(opts, logger, st)
	if err != nil {
		return nil, err
	}

	replicaDB, err := OpenDB(&DBOptions{Replica: true, Config: opts.Config}, logger, st)
	if !errors.Is(err, ErrNoReplica) {
		if err != nil {
			return db, err
		}
		gormext.SetReplica(db, replicaDB)
	}
	return db, nil
}

func CloseDBAndReplicas(db *gorm.DB) error {
	rErr := gormext.CloseReplica(db)
	err := db.Close()

	if rErr != nil || err != nil {
		return errors.Errorf("error closing db connections, primary: %s, replica: %s", err.Error(), rErr.Error())
	}
	return nil
}

// mysqlLogger is a wrapper around our internal `github/go/go-log` library to
// allow us to log go-sql-driver/mysql specific messages
type mysqlLogger struct {
	log log.Logger
}

// Print satisfies the mysql.Logger interface
func (m *mysqlLogger) Print(values ...interface{}) {
	// the Go mysql driver internally uses a global variable called `errLog`
	// that logs only errors, hence we're passing down them as kvp.Err()
	m.log.WithError(errors.New(fmt.Sprint(values...))).Error("mysql go driver error")
}
