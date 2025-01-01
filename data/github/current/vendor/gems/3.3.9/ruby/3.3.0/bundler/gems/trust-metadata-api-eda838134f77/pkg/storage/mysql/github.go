package mysql

import (
	"context"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/go-sql-driver/mysql"
)

func fromListAttestationsByOwnerSubjectDigestRowToSQLCAttestation(sqlcAttestation *sqlc.ListAttestationsByOwnerSubjectDigestRow) sqlc.Attestation {
	return sqlc.Attestation{
		ID:            sqlcAttestation.ID,
		DomainID:      sqlcAttestation.DomainID,
		Purl:          sqlcAttestation.Purl,
		OwnerID:       sqlcAttestation.OwnerID,
		RepositoryID:  sqlcAttestation.RepositoryID,
		TenantID:      sqlcAttestation.TenantID,
		SubjectDigest: sql.NullString{String: sqlcAttestation.SubjectDigest, Valid: true},
		SubjectName:   sql.NullString{String: sqlcAttestation.SubjectName, Valid: true},
		Certificate:   sqlcAttestation.Certificate,
		MediaType:     sqlcAttestation.MediaType,
		PredicateType: sqlcAttestation.PredicateType,
		StatementType: sqlcAttestation.StatementType,
		Statement:     sqlcAttestation.Statement,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}
}

func parseListAttestationsByOwnerSubjectDigestRowToSQLC(sqlAttestations []sqlc.ListAttestationsByOwnerSubjectDigestRow) []sqlc.Attestation {
	sqlcAttestations := make([]sqlc.Attestation, len(sqlAttestations))

	for i := range sqlAttestations {
		sqlcAttestation := fromListAttestationsByOwnerSubjectDigestRowToSQLCAttestation(&sqlAttestations[i])
		sqlcAttestations[i] = sqlcAttestation
	}

	return sqlcAttestations
}

/*
  GitHub API Queries
*/

// ListAttestationsByOwnerSubjectDigest retrieves the attestation from the MySQL database with given subject digest.
func (d *LiveDatabase) ListAttestationsByOwnerSubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationsByOwnerSubjectDigest")
	defer span.End()

	// retrieve from database
	tx := sqlc.New(d.db)

	fetchDirection := cursor.GetFetchDirection()
	limit := cursor.GetQueryLimit()

	params := sqlc.ListAttestationsByOwnerSubjectDigestParams{
		After:         uint64(cursor.After),
		Before:        uint64(cursor.Before),
		DomainID:      uint32(identifiers.DomainID),
		OwnerID:       convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID:  convertToSQLNullInt64(identifiers.RepositoryID),
		SubjectDigest: identifiers.SubjectDigest,
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: limit,
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: fetchDirection,
	}

	sqlAttestationsBySubjectDigest, err := tx.ListAttestationsByOwnerSubjectDigest(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	// convert to attestation.Record type
	sqlcAttestations := parseListAttestationsByOwnerSubjectDigestRowToSQLC(sqlAttestationsBySubjectDigest)
	attestations, err := parseAttestations(sqlcAttestations)

	if err != nil {
		return nil, nil, ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

// GetAttestationByRepository retrieves the attestation from the MySQL database with a given ID
func (d *LiveDatabase) GetAttestationByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationByRepository")
	defer span.End()

	tx := sqlc.New(d.db)

	params := sqlc.GetAttestationByRepositoryParams{
		ID:           identifiers.ID,
		DomainID:     uint32(identifiers.DomainID),
		OwnerID:      convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID: convertToSQLNullInt64(identifiers.RepositoryID),
	}

	sqlAttestation, err := tx.GetAttestationByRepository(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	attestation, err := fromSQLCGetAttestationByRepositoryRow(&sqlAttestation)
	if err != nil {
		return nil, ErrConvertFromSQLC{err, sqlAttestation.ID}
	}

	return &attestation, nil
}

// GetAttestationSummaryByRepository retrieves selected columns for the attestation record from the MySQL database with a given ID
func (d *LiveDatabase) GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationSummaryByRepository")
	defer span.End()

	tx := sqlc.New(d.db)

	params := sqlc.GetAttestationSummaryByRepositoryParams{
		ID:           identifiers.ID,
		DomainID:     uint32(identifiers.DomainID),
		OwnerID:      convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID: convertToSQLNullInt64(identifiers.RepositoryID),
	}

	sqlAttestation, err := tx.GetAttestationSummaryByRepository(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	attestation, err := fromSQLCGetAttestationSummaryByRepositoryRow(&sqlAttestation)
	if err != nil {
		return nil, ErrConvertFromSQLC{err, sqlAttestation.ID}
	}

	return &attestation, nil
}

// ListAttestationsByRepository retrieves the attestation from the MySQL database with given owner id and repository id.
func (d *LiveDatabase) ListAttestationsByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_ListAttestationsByRepository")
	defer span.End()

	// retrieve from database
	tx := sqlc.New(d.db)

	fetchDirection := cursor.GetFetchDirection()
	limit := cursor.GetQueryLimit()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	params := sqlc.ListAttestationsByRepositoryParams{
		After:        uint64(cursor.After),
		Before:       uint64(cursor.Before),
		DomainID:     uint32(identifiers.DomainID),
		OwnerID:      convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID: convertToSQLNullInt64(identifiers.RepositoryID),
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: limit,
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: fetchDirection,
	}

	sqlAttestationsBatch, err := tx.ListAttestationsByRepository(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch attestation records in MySQL: %d", fetchDurationTime), kvp.String("Domain", "GitHub"))

	attestations, err := parseListAttestationsByRepositoryRow(sqlAttestationsBatch)
	if err != nil {
		return nil, nil, ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

// ListAttestationSummariesByRepository retrieves the attestation from the MySQL database with given subject digest.
func (d *LiveDatabase) ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_ListAttestationSummariesByRepository")
	defer span.End()

	// retrieve from database
	tx := sqlc.New(d.db)

	fetchDirection := cursor.GetFetchDirection()
	limit := cursor.GetQueryLimit()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	params := sqlc.ListAttestationSummariesByRepositoryParams{
		After:        uint64(cursor.After),
		Before:       uint64(cursor.Before),
		DomainID:     uint32(identifiers.DomainID),
		OwnerID:      convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID: convertToSQLNullInt64(identifiers.RepositoryID),
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: limit,
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: fetchDirection,
	}

	sqlAttestationsBatch, err := tx.ListAttestationSummariesByRepository(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch attestation records in MySQL: %d", fetchDurationTime), kvp.String("Domain", "GitHub"))

	attestations, err := parseListAttestationSummariesByRepositoryRow(sqlAttestationsBatch)
	if err != nil {
		return nil, nil, ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

/*
  GitHub Query Helper Functions
*/

// fromSQLCGetAttestationSummaryByRepositoryRow converts from the sqlc.fromSQLCGetAttestationSummaryByRepositoryRow type to the attestation.Record type.
func fromSQLCGetAttestationSummaryByRepositoryRow(sqlcAttestation *sqlc.GetAttestationSummaryByRepositoryRow) (attestation.Record, error) {
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
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		SubjectDigest: sqlcAttestation.SubjectDigest,
		SubjectName:   sqlcAttestation.SubjectName,
		Certificate:   cert,
		PredicateType: sqlcAttestation.PredicateType,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}, nil
}

// StoreAttestation adds an attestation to the MySQL database with
// a provided transaction
func (d *LiveDatabase) StoreAttestation(ctx context.Context, attestation *attestation.Record, tx *sql.Tx) (uint64, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_StoreAttestation")
	defer span.End()

	// cast to sqlc type
	a, err := toSQLC(attestation)
	if err != nil {
		return 0, ErrConvertToSQLC{err}
	}

	// store in database
	// create a new timer to capture the duration it takes to store the attestation record in MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	qtx := sqlc.New(tx)
	sqlResult, err := qtx.StoreAttestation(ctx, a)

	if err != nil {
		d.logger.Info("Failed to store attestation record in MySQL", kvp.Uint64("Record-ID", attestation.ID), kvp.String("Domain", "GitHub"))

		var mysqlError *mysql.MySQLError
		if errors.As(err, &mysqlError) && mysqlError.Number == uint16(1062) {
			return 0, ErrDuplicateAttestation
		}

		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToStoreRecord, nil, 1)

		return 0, ErrStoreRecord{err}
	}

	// if record fetch succeeded, record zero to the failed store metric
	d.metrics.Counter(metricFailedToStoreRecord, nil, 0)

	// capture the duration in milliseconds it takes to store the attestation record in MySQL
	// and send it to DataDog as a timing metric
	storeDurationTime := metricTimer.Time("attestation_record_stored_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to store attestation record in MySQL: %d", storeDurationTime), kvp.Uint64("Record-ID", attestation.ID), kvp.String("Domain", "GitHub"))

	// get the ID of the stored record
	idInt64, err := sqlResult.LastInsertId()
	if err != nil {
		return 0, ErrStoreRecord{err}
	}

	return castToUInt64(idInt64), nil
}
