package gormext

import (
	"context"

	"github.com/jinzhu/gorm"
)

// SetReplica stores a replica connection against this db instance.
func SetReplica(db *gorm.DB, replicaDB *gorm.DB) {
	db.InstantSet("gormext.replica", replicaDB)
}

// CloseReplica will close any replica connection associated with this db instance.
func CloseReplica(db *gorm.DB) error {
	if replica, ok := GetReplica(db); ok {
		return replica.Close()
	}
	return nil
}

type gormextKey string

var tryReplica gormextKey = "gormext.try_replica"

// WithTryReplica hints that any methods given this context that could use a replica connection should try.
func WithTryReplica(ctx context.Context, v bool) context.Context {
	return context.WithValue(ctx, tryReplica, v)
}

// TryGetReplica will try and return a replica connection if available, otherwise it will return the connection
// that was passed in.
func TryGetReplica(ctx context.Context, db *gorm.DB) *gorm.DB {
	if v, ok := ctx.Value(tryReplica).(bool); ok && v {
		if replicaDB, ok := GetReplica(db); ok {
			return replicaDB
		}
	}

	return db
}

// GetReplica returns the replica connection if available.
func GetReplica(db *gorm.DB) (*gorm.DB, bool) {
	v, ok := db.Get("gormext.replica")
	if !ok {
		return nil, ok
	}
	replicaDB, ok := v.(*gorm.DB)
	if !ok {
		return nil, ok
	}
	return replicaDB, ok
}
