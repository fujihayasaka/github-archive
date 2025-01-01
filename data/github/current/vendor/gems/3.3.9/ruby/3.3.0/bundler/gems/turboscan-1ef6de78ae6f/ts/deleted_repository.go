package ts

import "github.com/SamuelTissot/sqltime"

type DeletedRepositoryID uint64

// DeletedRepository models a single gh/gh repository, that has been
// fully deleted (purged) from the gh/gh clusters.
// The turboscan data for such a repo should be eventually deleted as well,
// but a single row will be kept in this table for debugging/auditing
// purposes.
type DeletedRepository struct {
	BaseModel
	ID DeletedRepositoryID

	RepositoryID RepositoryEID
	// DeleteFinishedAt will be null when there is turboscan data
	// to delete otherwise it'll be set to the time when the deletion
	// finished
	DeleteFinishedAt *sqltime.Time
	DbRowsDeleted    uint64
	EsDocsDeleted    uint64
	BlobsDeleted     uint64
}
