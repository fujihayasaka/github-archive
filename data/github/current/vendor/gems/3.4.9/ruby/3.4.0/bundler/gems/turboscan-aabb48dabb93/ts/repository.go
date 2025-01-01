package ts

import (
	"bytes"
	"context"
	"database/sql"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
)

type RepositoryMetadataID uint64

// Repository models a single gh/gh repository. It contains metadata
// which will eventually be synched with dotcom.
// There is no guarantee that all analysed repositories
// are present in this table.
type Repository struct {
	BaseModel
	ID RepositoryMetadataID

	RepositoryID        RepositoryEID
	OwnerID             OwnerEID
	CodeScanningEnabled bool
	SourceUpdatedAt     sqltime.Time
	DefaultRef          []byte
	Visibility          sql.NullString `json:"visibility" sql:"type:ENUM('public', 'private', 'internal')"`
	// LastIndexedAt records the last time a _full_ reindex ws performed.
	LastIndexedAt sql.NullTime
}

// Indexer is the abstract interface for syncing alerts and repository metadata to ElasticSearch
type Indexer interface {
	IndexDocuments(ctx context.Context, index Index, docs []*SearchDocument) error
	UpdateRepositoryMetadata(ctx context.Context, repository Repository) error
}

func RepositoryVisibilityFromSecurityCenterProto(r entities.Repository_Visibility) sql.NullString {
	switch r {
	case entities.Repository_PUBLIC:
		return sql.NullString{String: "public", Valid: true}
	case entities.Repository_PRIVATE:
		return sql.NullString{String: "private", Valid: true}
	case entities.Repository_INTERNAL:
		return sql.NullString{String: "internal", Valid: true}
	case entities.Repository_VISIBILITY_UNKNOWN:
		fallthrough
	default:
		return sql.NullString{Valid: false}
	}
}

func (r *Repository) EqualMetadata(a *Repository) bool {
	return r.RepositoryID == a.RepositoryID &&
		r.OwnerID == a.OwnerID &&
		r.CodeScanningEnabled == a.CodeScanningEnabled &&
		r.Visibility.Valid == a.Visibility.Valid &&
		r.Visibility.String == a.Visibility.String &&
		bytes.Equal(r.DefaultRef, a.DefaultRef)
}
