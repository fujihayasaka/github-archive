//go:generate go run ../cmd/verifygenerator/ -d . -w verify.go . Analysis LogicalAlert PhysicalAlert Rule ToolVersion Tool CodeFlow CodeFlowsDocument RelatedLocation Snippet AlertLink Configuration

// Package ts contains shared structs.
package ts

import (
	"github.com/jinzhu/gorm"

	"golang.org/x/exp/slices"

	"github.com/SamuelTissot/sqltime"
)

const (
	DEFAULT_PAGE_SIZE uint32 = 30
	MAX_PAGE_SIZE     uint32 = 100
)

// SerializedCursor represents a serialized cursor for paginating resources.
type SerializedCursor struct {
	String     string
	Descending bool
}

// Pagination data
type Pagination struct {
	Limit  uint32
	Offset uint32
	Cursor *SerializedCursor
}

func (p *Pagination) Apply(db *gorm.DB) *gorm.DB {
	if p != nil {
		db = db.Limit(p.Limit)

		if p.Offset > 0 {
			db = db.Offset(p.Offset)
		}
	}
	return db
}

// FindOptions is passed to methods who require to specify how to find their
// resources.
type FindOptions struct {
	Pagination *Pagination
	Preloads   []string
	SortBy     string
}

func (opt *FindOptions) Apply(db *gorm.DB) *gorm.DB {
	query := db

	if opt != nil {
		query = opt.Pagination.Apply(db)

		if opt.SortBy != "" {
			query = query.Order(opt.SortBy)
		}

		for _, preload := range opt.Preloads {
			query = query.Preload(preload)
		}
	}

	return query
}

// Uint64 returns a pointer to v.
func Uint64(v uint64) *uint64 { return &v }

// BaseModel captures the properties that are common across all
// ts.
//
// Other model types should extend BaseModel as:
//
//	type NewType struct {
//	   BaseModel
//	   FieldA string
//	   ...
//	}
type BaseModel struct {
	// CreatedAt is the record creation time
	CreatedAt sqltime.Time
	// UpdatedAt is the latest record update time
	UpdatedAt sqltime.Time
}

// sorted returns a stable-sorted copy of items
func sorted[T interface{ Compare(T) int }](items []T) []T {
	out := make([]T, len(items))
	copy(out, items)
	slices.SortStableFunc(out, T.Compare)
	return out
}
