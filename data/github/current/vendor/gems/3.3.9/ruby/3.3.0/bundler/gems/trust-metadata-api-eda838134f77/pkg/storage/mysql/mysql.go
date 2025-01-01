package mysql

import (
	"context"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"fmt"
	"math"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	in_toto "github.com/in-toto/attestation/go/v1"
	"google.golang.org/protobuf/encoding/protojson"
)

const (
	defaultCursorPerPage = int32(30)
)

// With current design, we always return attestations as DESC order by ID.
type Cursor struct {
	PerPage int32
	// Before takes an attestation ID and fetches the previous page of attestations given the current sort order of attestations (for the default DESC ID order, Before fetches IDs that are greater than Before ID)
	Before uint64
	// After takes an attestation ID and fetches the next page of attestations given the current sort order of attestations (for the default DESC ID order, After fetches IDs that are less than After ID)
	After uint64
}

func (c *Cursor) Validate() error {
	if c.PerPage <= 0 {
		c.PerPage = 1
	} else if c.PerPage > 100 {
		c.PerPage = 100
	}

	if c.After > 0 && c.Before > 0 {
		return fmt.Errorf("cannot set both After and Before")
	}
	return nil
}

func (c *Cursor) IsBefore() bool {
	return c.Before > 0
}

func (c *Cursor) GetQueryLimit() int32 {
	if c.PerPage <= 0 {
		return 0
	}
	return c.PerPage + 1
}

// this function returns the order by direction for fetching the next page of attestations
func (c *Cursor) GetFetchDirection() string {
	if c.IsBefore() {
		return "ASC"
	}
	return "DESC"
}

func NewCursorFromRequest(rpcPerPage uint32, rpcAfter uint64, rpcBefore uint64) (*Cursor, error) {
	if rpcPerPage > math.MaxInt32 {
		return nil, fmt.Errorf("invalid PerPage value: %d", rpcPerPage)
	}

	// nolint:gosec // we ensured that this should not overflow
	perPage := int32(rpcPerPage)

	if perPage == 0 {
		perPage = defaultCursorPerPage // default PerPage
	}

	cursor := &Cursor{
		PerPage: perPage,
	}

	if rpcAfter > 0 {
		cursor.After = rpcAfter
	}

	if rpcBefore > 0 {
		cursor.Before = rpcBefore
	}

	err := cursor.Validate()

	if err != nil {
		return nil, err
	}

	return cursor, nil
}

type LiveDatabase struct {
	db      sqlc.DBTX
	logger  log.Logger
	metrics stats.Client
}

var _ Database = &LiveDatabase{}

// NewLiveDatabase creates a MySQL implementation of the Database interface.
func NewLiveDatabase(uri string, logger log.Logger, metrics stats.Client) (*LiveDatabase, error) {
	db, err := sql.Open("mysql", uri)
	if err != nil {
		return nil, ErrMySQLConn{err}
	}

	// See docs for more information: https://github.com/github/go/blob/main/docs/database_access.md
	db.SetConnMaxIdleTime(25 * time.Second)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetMaxIdleConns(32)
	db.SetMaxOpenConns(64)

	return NewLiveDatabaseFromConn(db, logger, metrics), nil
}

// NewLiveDatabaseFromDB creates a LiveDatabase from an existing database connection.
func NewLiveDatabaseFromConn(db sqlc.DBTX, logger log.Logger, metrics stats.Client) *LiveDatabase {
	return &LiveDatabase{
		db:      db,
		logger:  logger,
		metrics: metrics,
	}
}

// GetDB returns the underlying database connection.
func (d *LiveDatabase) GetDB() *sql.DB {
	return d.db.(*sql.DB)
}

// Close closes the MySQL database connection.
func (d *LiveDatabase) Close() error {
	err := d.db.(*sql.DB).Close()
	if err != nil {
		return ErrMySQLClose{err}
	}
	return nil
}

func (d *LiveDatabase) StoreAttestationSubjects(ctx context.Context, attestationID uint64, subjects []attestation.Subject, tx *sql.Tx) error {
	// create the insert statement
	insertSubjectsStatement := "INSERT INTO attestations_subjects (attestation_id, subject_name, subject_digest) VALUES "
	var values []interface{}

	// loop through the subjects and add them to the statement
	for i, subject := range subjects {
		if i > 0 {
			insertSubjectsStatement += ", "
		}
		insertSubjectsStatement += "(?, ?, ?)"
		values = append(values, attestationID, subject.Name, subject.SubjectDigest.String())
	}
	insertSubjectsStatement += ";"

	// execute the insert statement, if it fails, return an error to the caller and expect the caller to rollback the transaction
	_, err := tx.ExecContext(ctx, insertSubjectsStatement, values...)
	if err != nil {
		return fmt.Errorf("failed to commit MySQL attestation subject record insert: %w", err)
	}

	return nil
}

func calculatePageInfo(cursor *Cursor, attestations []attestation.Record) ([]attestation.Record, *attestation.PageInfo, error) {
	// to clean the attestations and return only the requested records with pagination information
	if len(attestations) == 0 {
		return attestations, nil, nil
	}

	// Step 1: check if there are more records than requested
	hasMore := false
	// to set hasMore to true if there are more records than requested
	if cursor.PerPage > 0 && len(attestations) > int(cursor.PerPage) {
		hasMore = true
		// Step 2: slice the records with requested page size
		// We need to slice out the first or last record as we fetched perPage + 1 to
		// compute "hasMore" depending on the QUERY order (returned order is always DESC),
		// when fetching with before (backwards) we query ASC so we slice out the first item,
		// when fetching with after (forwards) we query DESC so we slice out the last item
		if cursor.IsBefore() {
			attestations = attestations[1:]
		} else {
			attestations = attestations[:cursor.PerPage]
		}
	}

	// Step 3: construct the page info
	pageInfo := &attestation.PageInfo{}

	// if there are more records than requested, set hasMore to true based on the query order
	if hasMore {
		if cursor.IsBefore() {
			pageInfo.HasPreviousPage = true
		} else {
			pageInfo.HasNextPage = true
		}
	}

	// set the start and end cursor positions
	if len(attestations) > 0 {
		pageInfo.StartCursor = attestations[0].ID
		pageInfo.EndCursor = attestations[len(attestations)-1].ID
	}
	return attestations, pageInfo, nil
}

// convertToSQLNullStr converts a string to a sql.NullString.
func convertToSQLNullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{
			Valid:  false,
			String: s,
		}
	}

	return sql.NullString{Valid: true, String: s}
}

// convertToSQLNullInt64 converts an int64 to a sql.NullInt64.
func convertToSQLNullInt64(i *uint64) sql.NullInt64 {
	// Go doesn't support unsigned integers in database/sql, so we have to cast to signed int64.
	// See: https://github.com/golang/go/issues/47953 & potentially use a Generic later?
	if i == nil {
		return sql.NullInt64{
			Valid: false,
			Int64: 0,
		}
	}

	//nolint:gosec // see comment above
	signedInt := int64(*i)
	return sql.NullInt64{Valid: true, Int64: signedInt}
}

// convertToUInt64 converts a sql.NullInt64 to a uint64 because database/sql doesn't have a NullUInt64 type.
func convertToUInt64(i sql.NullInt64) *uint64 {
	// Go doesn't support unsigned integers in database/sql, so we have to cast between signed/unsigned int64.
	// See: https://github.com/golang/go/issues/47953
	if !i.Valid {
		return nil
	}

	//nolint:gosec // see comment above
	unsignedInt := uint64(i.Int64)
	return &unsignedInt
}

// castToUInt64 converts an int64 to a uint64.
func castToUInt64(i int64) uint64 {
	// Go doesn't support unsigned integers in database/sql, so we have to cast to unsigned int64.
	// This is used at our database layer to convert the ID from the database to a uint64 for the attestation.Record type.
	// It should be used with caution to avoid overflow.

	// G115: integer overflow conversion int64 -> uint64
	//nolint:gosec
	return uint64(i)
}

// convertToString converts a sql.NullString to a string
func convertToString(i sql.NullString) string {
	if !i.Valid {
		return ""
	}

	return i.String
}

// parseListAttestationsByRepositoryRow parses from the sqlc.ListAttestationsByRepositoryRow database type into the attestation.Record type.
func parseListAttestationsByRepositoryRow(sqlAttestations []sqlc.ListAttestationsByRepositoryRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i := range sqlAttestations {
		attestation, err := fromSQLCListAttestationsByRepositoryRow(&sqlAttestations[i])
		if err != nil {
			return nil, ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = attestation
	}

	return attestations, nil
}

// parseListAttestationSummariesByRepositoryRow parses from the sqlc.ListAttestationSummariesByRepositoryRow database type into the attestation.Record type.
func parseListAttestationSummariesByRepositoryRow(sqlAttestations []sqlc.ListAttestationSummariesByRepositoryRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i := range sqlAttestations {
		attestation, err := fromSQLCListAttestationSummariesByRepositoryRow(&sqlAttestations[i])
		if err != nil {
			return nil, ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = attestation
	}

	return attestations, nil
}

// parseAttestations parses the attestations from the sqlc database type into the attestation.Record type.
func parseAttestations(sqlAttestations []sqlc.Attestation) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i := range sqlAttestations {
		attestation, err := fromSQLC(&sqlAttestations[i])
		if err != nil {
			return nil, ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = attestation
	}

	return attestations, nil
}

// fromSQLC converts from the sqlc type to the attestation.Record type.
func fromSQLC(sqlcAttestation *sqlc.Attestation) (attestation.Record, error) {
	var cert *x509.Certificate
	var err error

	if len(sqlcAttestation.Certificate.String) > 0 {
		derBytes, err := base64.StdEncoding.DecodeString(sqlcAttestation.Certificate.String)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to base64 decode certificate: %w", err)
		}
		cert, err = x509.ParseCertificate(derBytes)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to parse certificate: %w", err)
		}
	}

	statement := &in_toto.Statement{}
	err = protojson.Unmarshal([]byte(sqlcAttestation.Statement), statement)
	if err != nil {
		return attestation.Record{}, fmt.Errorf("failed to unmarshal statement: %w", err)
	}

	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		DomainID:      sqlcAttestation.DomainID,
		Purl:          sqlcAttestation.Purl.String,
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		SubjectDigest: convertToString(sqlcAttestation.SubjectDigest),
		SubjectName:   convertToString(sqlcAttestation.SubjectName),
		Certificate:   cert,
		MediaType:     sqlcAttestation.MediaType,
		PredicateType: sqlcAttestation.PredicateType,
		StatementType: sqlcAttestation.StatementType,
		Statement:     statement,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}, nil
}

// toSQLC converts from the attestation.Record type to the sqlc type.
func toSQLC(record *attestation.Record) (sqlc.StoreAttestationParams, error) {
	var certB64 string

	stmtBytes, err := protojson.Marshal(record.Statement)
	if err != nil {
		return sqlc.StoreAttestationParams{}, fmt.Errorf("failed to marshal statement: %w", err)
	}

	if record.Certificate != nil {
		certB64 = base64.StdEncoding.EncodeToString(record.Certificate.Raw)
	}

	domainID := uint32(record.DomainID)

	return sqlc.StoreAttestationParams{
		DomainID:      domainID,
		Purl:          convertToSQLNullStr(record.Purl),
		OwnerID:       convertToSQLNullInt64(record.OwnerID),
		RepositoryID:  convertToSQLNullInt64(record.RepositoryID),
		TenantID:      record.TenantID,
		Certificate:   convertToSQLNullStr(certB64),
		MediaType:     record.MediaType,
		PredicateType: record.PredicateType,
		StatementType: record.StatementType,
		Statement:     string(stmtBytes),
		CreatedAt:     record.CreatedAt,
	}, nil
}

// fromSQLCListAttestationsByRepositoryRow converts from the sqlc.ListAttestationsByRepositoryRow type to the attestation.Record type.
func fromSQLCListAttestationsByRepositoryRow(sqlcAttestation *sqlc.ListAttestationsByRepositoryRow) (attestation.Record, error) {
	var cert *x509.Certificate

	if len(sqlcAttestation.Certificate.String) > 0 {
		derBytes, err := base64.StdEncoding.DecodeString(sqlcAttestation.Certificate.String)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to base64 decode certificate: %w", err)
		}
		cert, err = x509.ParseCertificate(derBytes)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to parse certificate: %w", err)
		}
	}
	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		DomainID:      sqlcAttestation.DomainID,
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		SubjectDigest: sqlcAttestation.SubjectDigest,
		SubjectName:   sqlcAttestation.SubjectName,
		Certificate:   cert,
		PredicateType: sqlcAttestation.PredicateType,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}, nil
}

// fromSQLCListAttestationSummariesByRepositoryRow converts from the sqlc.ListAttestationSummariesByRepositoryRow type to the attestation.Record type.
func fromSQLCListAttestationSummariesByRepositoryRow(sqlcAttestation *sqlc.ListAttestationSummariesByRepositoryRow) (attestation.Record, error) {
	var cert *x509.Certificate

	if len(sqlcAttestation.Certificate.String) > 0 {
		derBytes, err := base64.StdEncoding.DecodeString(sqlcAttestation.Certificate.String)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to base64 decode certificate: %w", err)
		}
		cert, err = x509.ParseCertificate(derBytes)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to parse certificate: %w", err)
		}
	}
	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		DomainID:      sqlcAttestation.DomainID,
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		Certificate:   cert,
		PredicateType: sqlcAttestation.PredicateType,
		CreatedAt:     sqlcAttestation.CreatedAt,
		SubjectCount:  castToUInt64(sqlcAttestation.SubjectCount),
	}, nil
}

// fromSQLCGetAttestationByRepositoryRow converts from the sqlc.GetAttestationByRepositoryRow type to the attestation.Record type.
func fromSQLCGetAttestationByRepositoryRow(sqlcAttestation *sqlc.GetAttestationByRepositoryRow) (attestation.Record, error) {
	var cert *x509.Certificate

	if len(sqlcAttestation.Certificate.String) > 0 {
		derBytes, err := base64.StdEncoding.DecodeString(sqlcAttestation.Certificate.String)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to base64 decode certificate: %w", err)
		}
		cert, err = x509.ParseCertificate(derBytes)
		if err != nil {
			return attestation.Record{}, fmt.Errorf("failed to parse certificate: %w", err)
		}
	}
	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		DomainID:      sqlcAttestation.DomainID,
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		SubjectDigest: sqlcAttestation.SubjectDigest,
		SubjectName:   sqlcAttestation.SubjectName,
		Certificate:   cert,
		PredicateType: sqlcAttestation.PredicateType,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}, nil
}
