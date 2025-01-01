package mysql

import (
	"database/sql"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

// Row is a struct that represents a row in the attestations table
// The content of sql.Rows is scanned into this struct
// Currently this is only used by the LiveDatabase#ListAttestationSummariesByRepositoryWithFilters
// method and so it currently only includes columns fetched by that method
type Row struct {
	Certificate   sql.NullString `db:"certificate"`
	CreatedAt     time.Time      `db:"created_at"`
	DomainID      uint32         `db:"domain_id"`
	ID            uint64         `db:"id"`
	OwnerID       uint64         `db:"owner_id"`
	PredicateType string         `db:"predicate_type"`
	RepositoryID  uint64         `db:"repository_id"`
	TenantID      uint64         `db:"tenant_id"`
	TotalRows     int64          `db:"total_rows"`
	SubjectCount  uint64         `db:"subject_count"`
	SubjectName   string         `db:"subject_name"`
}

func (r *Row) ToRecord() (attestation.Record, error) {
	ownerID := r.OwnerID
	repositoryID := r.RepositoryID
	cert, err := toX509Cert(r.Certificate)
	if err != nil {
		return attestation.Record{}, err
	}
	return attestation.Record{
		Certificate:   cert,
		CreatedAt:     r.CreatedAt,
		ID:            r.ID,
		OwnerID:       &ownerID,
		PredicateType: r.PredicateType,
		RepositoryID:  &repositoryID,
		SubjectCount:  r.SubjectCount,
		SubjectName:   r.SubjectName,
		Subjects: []attestation.Subject{
			{
				Name: r.SubjectName,
			},
		},
		TenantID:   r.TenantID,
		TotalCount: r.TotalRows,
	}, nil
}
