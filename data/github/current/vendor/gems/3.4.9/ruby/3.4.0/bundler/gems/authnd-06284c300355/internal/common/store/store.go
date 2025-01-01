package store

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/github-telemetry-go/kvp"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// Store common interface for looking up and acting on database records
type Store interface {
	Mysql1Store
	ProgrammaticAccessTokensStore
	MobileDeviceKeysStore
	MobileDeviceAuthRequestsStore
	ScopedIntegrationInstallationsStore
	AuthenticationTokensStore
}

// Store methods for data owned by the mysql1 cluster
type Mysql1Store interface {
	UsersStore
	UserSessionsStore
	OAuthAccessesStore
	OrganizationCredentialAuthorizationsStore
	PublicKeysStore
	BusinessesStore
	IntegrationsStore
	IntegrationInstallationsStore
}

type enterpriseStore struct {
	store store
}

type store struct {
	resolver  mysql.Resolver
	isProxima bool
}

// DatabaseGetter is an interface for getting a *sqlx.DB by schema name, primarily implemented by db.Provider.
type DatabaseGetter interface {
	GetDB(schema string) (*sqlx.DB, error)
}

// NewStore returns a new Store backed by the supplied database connections.
func NewStore(databaseGetter DatabaseGetter, isEnterpriseServer bool) (Store, error) {
	return newStore(databaseGetter, false, nil, isEnterpriseServer, false)
}

// NewPrimaryReadStore return a new Store backed by the supplied database connections, which will
// read from primary when the cluster is unhealthy (indicated by the provided freno.Throttler).
// The primary reads may either be done preemptively or on an expected error, depending on configured policy.
func NewPrimaryReadStore(databaseGetter DatabaseGetter, throttler freno.Throttler, isEnterpriseServer bool) (Store, error) {
	return newStore(databaseGetter, true, throttler, isEnterpriseServer, false)
}

// NewProximaStore returns a new Store backed by the supplied database connections.
func NewProximaStore(databaseGetter DatabaseGetter) (Store, error) {
	return newStore(databaseGetter, false, nil, false, true)
}

func newStore(databaseGetter DatabaseGetter, fallbackToPrimaryReads bool, throttler freno.Throttler, isEnterpriseServer, isProxima bool) (Store, error) {
	// TODO(chriskirkland): We should support a subset of schemas (configured in the DatabaseGetter) rather than requiring all of them
	// for runtimes that don't need them (i.e. the notifier job).
	authndRODb, err := databaseGetter.GetDB(schemas.AuthndRO)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.AuthndRO)
	}
	authndROEx := mysql.NewDefaultExecutor(schemas.AuthndRO, authndRODb)

	authndRWDb, err := databaseGetter.GetDB(schemas.AuthndRW)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.AuthndRW)
	}
	authndRWEx := mysql.NewDefaultExecutor(schemas.AuthndRW, authndRWDb)

	mysql1RODb, err := databaseGetter.GetDB(schemas.Mysql1RO)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.Mysql1RO)
	}
	mysql1ROEx := mysql.NewDefaultExecutor(schemas.Mysql1RO, mysql1RODb)
	//TODO(chriskirkland): add mysql1 read-only primary connection which can be done with existing RO connections

	collabRODb, err := databaseGetter.GetDB(schemas.CollabRO)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.CollabRO)
	}
	collabROEx := mysql.NewDefaultExecutor(schemas.CollabRO, collabRODb)

	collabRWDb, err := databaseGetter.GetDB(schemas.CollabRW)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.CollabRW)
	}
	collabRWEx := mysql.NewDefaultExecutor(schemas.CollabRW, collabRWDb)

	lodgeRODb, err := databaseGetter.GetDB(schemas.LodgeRO)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.LodgeRO)
	}
	lodgeROEx := mysql.NewDefaultExecutor(schemas.LodgeRO, lodgeRODb)

	lodgeRWDb, err := databaseGetter.GetDB(schemas.LodgeRW)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to get fetch DB for '%s' schema from provider", schemas.LodgeRW)
	}
	lodgeRWEx := mysql.NewDefaultExecutor(schemas.LodgeRW, lodgeRWDb)

	if fallbackToPrimaryReads {
		authndROEx = mysql.NewPrimaryReadsExecutor(authndROEx, authndRWEx, throttler)
		//TODO(chriskirkland): enable freno throttling for collab/lodge if we decide not to implement database selection https://github.com/github/authentication/issues/4228
		collabROEx = mysql.NewPrimaryReadsExecutor(collabROEx, collabRWEx, freno.DefaultThrottler)
		lodgeROEx = mysql.NewPrimaryReadsExecutor(lodgeROEx, lodgeRWEx, freno.DefaultThrottler)
	}

	var resolver mysql.Resolver
	if isProxima {
		resolver = mysql.NewProximaResolver(mysql1ROEx, authndROEx, collabROEx, lodgeROEx, mysql.NewTransactionExecutor(authndRWEx))
	} else {
		resolver = mysql.NewDefaultResolver(mysql1ROEx, authndROEx, collabROEx, lodgeROEx, mysql.NewTransactionExecutor(authndRWEx))
	}

	if isEnterpriseServer {
		return &enterpriseStore{
			store: store{resolver: resolver},
		}, nil
	} else {
		return &store{
			resolver:  resolver,
			isProxima: isProxima,
		}, nil
	}
}

// trackFindResult handles metrics and logging surrounding data look-up results
func (s *store) trackFindResult(ctx context.Context, conn, query string, timer *stats.Timer, err error) {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	var result string
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) || errors.Is(err, common.StoreErrUnsupported) {
			result = "not found"
		} else if errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			result = "ambiguous"
		} else {
			logger.WithError(err).Error("sql lookup attempted", kvp.String("gh.authnd.db.conn", conn), kvp.String("gh.authnd.db.query", query))
			result = "error"
		}
	} else {
		result = "success"
	}
	tags := stats.Tags{
		"query":  query,
		"result": result,
		"conn":   conn,
		"caller": mysql.GetFeatureSurfaceName(ctx),
		"table":  mysql.GetQueryTableName(ctx),
	}
	timer.Time("service.sql.find.duration", tags)
	statter.Counter("service.sql.find.count", tags, 1)
	logger.Debug("sql lookup attempted", kvp.String("gh.authnd.db.conn", conn), kvp.String("gh.authnd.db.query", query), kvp.String("gh.authnd.db.result", result))
}

// trackWriteResult handles metrics and logging surrounding write queries
func (s *store) trackWriteResult(ctx context.Context, conn, query string, timer *stats.Timer, err error) {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	result := "success"
	if err != nil {
		logger.WithError(err).Error("sql write attempted", kvp.String("gh.authnd.db.conn", conn), kvp.String("gh.authnd.db.query", query))
		result = "error"
	}

	tags := stats.Tags{
		"query":  query,
		"result": result,
		"conn":   conn,
		"caller": mysql.GetFeatureSurfaceName(ctx),
		"table":  mysql.GetQueryTableName(ctx),
	}
	timer.Time("service.sql.write.duration", tags)
	statter.Counter("service.sql.write.count", tags, 1)
	logger.Debug("sql write attempted", kvp.String("gh.authnd.db.conn", conn), kvp.String("gh.authnd.db.query", query), kvp.String("gh.authnd.db.result", result))
}
