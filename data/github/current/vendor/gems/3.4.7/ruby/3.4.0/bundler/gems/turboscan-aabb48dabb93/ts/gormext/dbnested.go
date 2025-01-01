package gormext

import (
	"database/sql"

	"github.com/jinzhu/gorm"
)

type NestedDB interface {
	DB() *sql.DB
}

// GetDB returns the underlying DB connection even if it is nested in a wrapper.
func GetDB(db *gorm.DB) *sql.DB {
	switch v := db.CommonDB().(type) {
	case *sql.DB:
		return v
	case NestedDB:
		return v.DB()
	}
	return nil
}
