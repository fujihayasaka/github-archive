// Package migrationctx provides utilities for working with migration contexts
package migrationctx

import (
	"errors"
	"fmt"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// MigrationContextGetter is an interface for getting the migration context
type MigrationContextGetter interface {
	GetMigrationContext() *v1.MigrationContext
}

var (
	// ErrEnterpriseIDEmpty is returned when the enterprise id is empty
	ErrEnterpriseIDEmpty = errors.New("enterprise id is empty")

	// ErrAdminUserIDEmpty is returned when the admin user id is empty
	ErrAdminUserIDEmpty = errors.New("admin user id is empty")
)

// Namespace returns the namespace for the given migration context
func Namespace(d MigrationContextGetter) (string, error) {
	if d.GetMigrationContext() == nil || d.GetMigrationContext().EnterpriseId == 0 {
		return "", ErrEnterpriseIDEmpty
	}
	return fmt.Sprintf("enterprise:%d", d.GetMigrationContext().EnterpriseId), nil
}

// AdminUserID returns the admin user id for the given migration context
func AdminUserID(d MigrationContextGetter) (int64, error) {
	if d.GetMigrationContext() == nil || d.GetMigrationContext().AdminUserId == 0 {
		return 0, ErrAdminUserIDEmpty
	}
	return d.GetMigrationContext().AdminUserId, nil
}
