package mysql

import (
	"context"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	in_toto "github.com/in-toto/attestation/go/v1"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/go-sql-driver/mysql"
)

const metricFailedToBeginTx = "mysql_attestation_begin_tx_fail_count"

var ErrReleaseAttestationConstraint = errors.New("release attestation constraint failed")

type LiveDatabase struct {
	db      sqlc.DBTX
	logger  log.Logger
	metrics stats.Client
}

// NewLiveDatabase creates a MySQL implementation of the Database interface.
func NewLiveDatabase(uri string, logger log.Logger, metrics stats.Client) (*LiveDatabase, error) {
	db, err := sql.Open("mysql", uri)
	if err != nil {
		return nil, &ErrMySQLConn{err}
	}

	// See docs for more information: https://github.com/github/go/blob/main/docs/database_access.md
	db.SetConnMaxIdleTime(25 * time.Second)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetMaxIdleConns(32)
	db.SetMaxOpenConns(64)

	return NewLiveDatabaseFromConn(db, logger, metrics), nil
}

// NewLiveDatabaseFromConn creates a LiveDatabase from an existing database connection.
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

// BeginTx starts a transaction via the underlying database connection.
func (d *LiveDatabase) BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error) {
	tx, err := d.db.(*sql.DB).BeginTx(ctx, opts)

	if err != nil {
		d.metrics.Counter(metricFailedToBeginTx, nil, 1)
		return nil, err
	}
	d.metrics.Counter(metricFailedToBeginTx, nil, 0)

	return tx, nil
}

// Close closes the MySQL database connection.
func (d *LiveDatabase) Close() error {
	err := d.db.(*sql.DB).Close()
	if err != nil {
		return &ErrMySQLClose{err}
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
		values = append(values, attestationID, subject.Name, subject.String())
	}
	insertSubjectsStatement += ";"

	// execute the insert statement, if it fails, return an error to the caller and expect the caller to rollback the transaction
	_, err := tx.ExecContext(ctx, insertSubjectsStatement, values...)
	if err != nil {
		return fmt.Errorf("failed to commit MySQL attestation subject record insert: %w", err)
	}

	return nil
}

func (d *LiveDatabase) StoreRelease(ctx context.Context, id uint64, release *attestation.Record, tx *sql.Tx) error {
	if release.RepositoryID == nil {
		return fmt.Errorf("repository ID is required for release attestation")
	}
	qtx := sqlc.New(tx)
	_, err := qtx.StoreRelease(ctx, sqlc.StoreReleaseParams{
		AttestationID: id,
		TenantID:      release.TenantID,
		RepositoryID:  *release.RepositoryID,
		Tag:           release.Tag,
	})

	// MySQL error 1062 indicates a unique constraint violation
	var mysqlError *mysql.MySQLError
	if errors.As(err, &mysqlError) && mysqlError.Number == uint16(1062) {
		return ErrReleaseAttestationConstraint
	} else if err != nil {
		return fmt.Errorf("failed to commit MySQL attestation release record insert: %w", err)
	}

	return nil
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

// convertToSQLNullTime converts a time.Time object to a sql.NullTime object.
func convertToSQLNullTime(t time.Time) sql.NullTime {
	if t.IsZero() {
		return sql.NullTime{
			Valid: false,
			Time:  time.Time{},
		}
	}

	return sql.NullTime{Valid: true, Time: t}
}

// convertToSQLNullInt64 converts an int64 pointer to a sql.NullInt64.
func convertToSQLNullInt64(i *uint64) sql.NullInt64 {
	// Go doesn't support unsigned integers in database/sql, so we have to cast to signed int64.
	// See: https://github.com/golang/go/issues/47953 & potentially use a Generic later?
	if i == nil || *i == 0 {
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

// parseListAttestationSummariesByRepositoryRow parses from the sqlc.ListAttestationSummariesByRepositoryRow database type into the attestation.Record type.
func parseListAttestationSummariesByRepositoryRow(sqlAttestations []sqlc.ListAttestationSummariesByRepositoryRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i := range sqlAttestations {
		attestationRecord, err := fromSQLCListAttestationSummariesByRepositoryRow(&sqlAttestations[i])
		if err != nil {
			return nil, &ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = attestationRecord
	}

	return attestations, nil
}

// fromSQLC converts from the sqlc type to the attestation.Record type.
func fromSQLC(sqlcAttestation *sqlc.Attestation) (attestation.Record, error) {
	cert, err := toX509Cert(sqlcAttestation.Certificate)
	if err != nil {
		return attestation.Record{}, err
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
		Signer:        convertToSQLNullStr(record.Signer),
	}, nil
}

// fromSQLCListAttestationSummariesByRepositoryRow converts from the sqlc.ListAttestationSummariesByRepositoryRow type to the attestation.Record type.
func fromSQLCListAttestationSummariesByRepositoryRow(row *sqlc.ListAttestationSummariesByRepositoryRow) (attestation.Record, error) {
	cert, err := toX509Cert(row.Certificate)
	if err != nil {
		return attestation.Record{}, err
	}

	return attestation.Record{
		ID:            uint64(row.ID),
		OwnerID:       convertToUInt64(row.OwnerID),
		DomainID:      row.DomainID,
		RepositoryID:  convertToUInt64(row.RepositoryID),
		TenantID:      row.TenantID,
		Certificate:   cert,
		PredicateType: row.PredicateType,
		CreatedAt:     row.CreatedAt,
		SubjectCount:  castToUInt64(row.SubjectCount),
		// We only care about returning the first subject name found
		// This subject name will be stored in the first element of the Subjects slice
		Subjects:   []attestation.Subject{{Name: row.SubjectName}},
		TotalCount: row.TotalRows,
	}, nil
}

// fromSQLCGetAttestationByRepositoryRow converts from the sqlc.GetAttestationByRepositoryRow type to the attestation.Record type.
func fromSQLCGetAttestationByRepositoryRow(sqlcAttestation *sqlc.GetAttestationByRepositoryRow) (attestation.Record, error) {
	cert, err := toX509Cert(sqlcAttestation.Certificate)
	if err != nil {
		return attestation.Record{}, err
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

// toX509Cert converts a sql.NullString to a *x509.Certificate
func toX509Cert(c sql.NullString) (*x509.Certificate, error) {
	if len(c.String) == 0 {
		return nil, nil
	}
	derBytes, err := base64.StdEncoding.DecodeString(c.String)
	if err != nil {
		return nil, fmt.Errorf("failed to base64 decode certificate: %w", err)
	}
	cert, err := x509.ParseCertificate(derBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse certificate: %w", err)
	}
	return cert, nil
}
