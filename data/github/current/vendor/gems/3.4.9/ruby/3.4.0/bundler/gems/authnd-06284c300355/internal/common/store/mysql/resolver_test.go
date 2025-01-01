package mysql

import (
	"context"
	"database/sql"
	"testing"

	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
)

func TestResolver(t *testing.T) {
	mysql1RO := testExecutor{name: "mysql1RO"}
	authndRO := testExecutor{name: "authndRO"}
	collabRO := testExecutor{name: "collabRO"}
	lodgeRO := testExecutor{name: "lodgeRO"}
	authndRW := testExecutor{name: "authndRW"}

	r := NewDefaultResolver(mysql1RO, authndRO, collabRO, lodgeRO, authndRW)
	pr := NewProximaResolver(mysql1RO, authndRO, collabRO, lodgeRO, authndRW)

	for table, expectedConn := range map[string]string{
		"integrations":                           "mysql1RO",
		"integration_installations":              "mysql1RO",
		"oauth_accesses":                         "mysql1RO",
		"oauth_applications":                     "mysql1RO",
		"organization_credential_authorizations": "mysql1RO",
		"public_keys":                            "mysql1RO",
		"user_sessions":                          "mysql1RO",
		"users":                                  "mysql1RO",
		"programmatic_access_tokens":             "authndRO",
		"mobile_device_keys":                     "authndRO",
		"mobile_auth_requests":                   "authndRO",
		"scoped_integration_installations":       "collabRO",
		"site_scoped_integration_installations":  "collabRO",
		"authentication_tokens":                  "lodgeRO",
	} {
		t.Run(table+" resolves to "+expectedConn, func(t *testing.T) {
			ex := r.ReadOnlyExecutorForTable(table)
			assert.Equal(t, expectedConn, ex.ConnectionName(), "%s in dotcom", table)

			if table != "mobile_device_keys" && table != "mobile_auth_requests" {
				pex := pr.ReadOnlyExecutorForTable(table)
				assert.Equal(t, expectedConn, pex.ConnectionName(), "%s in proxima", table)
			}
		})
	}
}

type testExecutor struct {
	name string
}

func (t testExecutor) ConnectionName() string {
	return t.name
}

func (t testExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return nil
}

func (t testExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return nil
}

func (t testExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	return nil
}

func (t testExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return nil, nil
}

func (t testExecutor) unwrap() (*sqlx.DB, error) {
	return nil, nil
}

func (t testExecutor) WithTransaction(ctx context.Context, fn func(Executor) error) error {
	return nil
}
