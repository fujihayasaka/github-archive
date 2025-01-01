package mysql

import (
	"context"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	in_toto "github.com/in-toto/attestation/go/v1"
	"google.golang.org/protobuf/encoding/protojson"
)

const (
	metricBatchFetchAttestationTime = "mysql_attestation_batch_fetch_duration"
	metricFetchedCount              = "mysql_fetched_record_count"
	metricFailedToDeleteRecordsByID = "mysql_failed_to_delete_records_by_id"
)

/*
  GitHub API Queries
*/

// NOTE: this function will be removed in a followup, see https://github.com/github/package-security/issues/2486
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
		PredicateType: identifiers.PredicateType,
		RepositoryID:  convertToSQLNullInt64(identifiers.RepositoryID),
		SubjectDigest: identifiers.SubjectDigest,
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: limit,
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: fetchDirection,
	}

	// Note that returned records will only be associated with one subject digests
	// Since we are not returning the subject digests through GitHub API endpoints
	// that call the ListAttestationsByOwnerSubjectDigest Twirp method, this seems
	// okay for now. It will need to be addressed in a follow up if the API
	// return object schema changes to include the subject digests.
	sqlAttestationsBySubjectDigest, err := tx.ListAttestationsByOwnerSubjectDigest(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, &ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	// convert to attestation.Record type
	attestations, err := convertListAttestationsByOwnerSubjectDigestRow(sqlAttestationsBySubjectDigest)
	if err != nil {
		return nil, nil, &ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

// ListAttestationsByOwnerSubjectDigests retrieves any attestation from the MySQL database with a subject digest
// present in the given list
func (d *LiveDatabase) ListAttestationsByOwnerSubjectDigests(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationsByOwnerSubjectDigests")
	defer span.End()

	// retrieve from database
	tx := sqlc.New(d.db)

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	fetchDirection := cursor.GetFetchDirection()
	limit := cursor.GetQueryLimit()

	params := sqlc.ListAttestationsByOwnerSubjectDigestsParams{
		After:          uint64(cursor.After),
		Before:         uint64(cursor.Before),
		DomainID:       uint32(identifiers.DomainID),
		OwnerID:        convertToSQLNullInt64(identifiers.OwnerID),
		PredicateType:  identifiers.PredicateType,
		RepositoryID:   convertToSQLNullInt64(identifiers.RepositoryID),
		SubjectDigests: identifiers.SubjectDigests,
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: limit,
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: fetchDirection,
	}

	records, err := tx.ListAttestationsByOwnerSubjectDigests(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, &ErrGetRecord{err}
	}

	// record how long the transaction took
	fetchDurationTime := metricTimer.Time(metricBatchFetchAttestationTime, nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch attestation records in MySQL: %d", fetchDurationTime), kvp.String("Domain", "GitHub"))
	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)
	// record the number of fetched records
	d.metrics.Counter(metricFetchedCount, nil, int64(len(records)))

	// convert to attestation.Record type
	attestations, err := convertListAttestationsByOwnerSubjectDigestsRow(records)
	if err != nil {
		return nil, nil, &ErrGetRecord{err}
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

		return nil, &ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	attestationRecord, err := fromSQLCGetAttestationByRepositoryRow(&sqlAttestation)
	if err != nil {
		return nil, &ErrConvertFromSQLC{err, sqlAttestation.ID}
	}

	return &attestationRecord, nil
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

	// retrieve the attestation record from the database
	sqlAttestation, err := tx.GetAttestationSummaryByRepository(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, &ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	attestationRecord, err := fromSQLCGetAttestationSummaryByRepositoryRow(&sqlAttestation)
	if err != nil {
		return nil, &ErrConvertFromSQLC{err, sqlAttestation.ID}
	}

	// retrieve the subjects for the attestation record from the database
	subjects, err := tx.GetSubjectByAttestation(ctx, attestationRecord.ID)
	if err != nil {
		return nil, &ErrGetRecord{err}
	}

	// add the subjects to the attestation record
	addSubjectsToAttestationRecord(&subjects, &attestationRecord)

	return &attestationRecord, nil
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
		After:              uint64(cursor.After),
		Before:             uint64(cursor.Before),
		Created:            identifiers.Created.Date,
		CreatedOperator:    identifiers.Created.Operator,
		DomainID:           uint32(identifiers.DomainID),
		OwnerID:            convertToSQLNullInt64(identifiers.OwnerID),
		PartialSubjectName: identifiers.SubjectName,
		PredicateType:      identifiers.PredicateType,
		RepositoryID:       convertToSQLNullInt64(identifiers.RepositoryID),
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

		return nil, nil, &ErrGetRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch attestation records in MySQL: %d", fetchDurationTime), kvp.String("Domain", "GitHub"))

	attestations, err := parseListAttestationSummariesByRepositoryRow(sqlAttestationsBatch)
	if err != nil {
		return nil, nil, &ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

func (d *LiveDatabase) DeleteAttestationsByID(ctx context.Context, attestationIDs []uint64, deletedAt time.Time) error {
	ctx, span := o11y.NamedSpan(ctx, "DB_DeleteAttestations")
	defer span.End()

	sqlNullDeletedAt := convertToSQLNullTime(deletedAt)
	params := sqlc.DeleteAttestationsByIdParams{
		AttestationIds: attestationIDs,
		DeletedAt:      sqlNullDeletedAt,
	}

	tx := sqlc.New(d.db)
	if _, err := tx.DeleteAttestationsById(ctx, params); err != nil {
		d.logger.Info("Failed to mark attestations as deleted", kvp.String("Domain", "GitHub"))
		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToDeleteRecordsByID, nil, 1)
		return err
	}
	return nil
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

// addSubjectsToAttestationRecord adds the subjects to the given attestation record.
func addSubjectsToAttestationRecord(sqlcSubjects *[]sqlc.GetSubjectByAttestationRow, record *attestation.Record) {
	for _, sqlcSubject := range *sqlcSubjects {
		record.Subjects = append(record.Subjects, attestation.Subject{
			Name: sqlcSubject.SubjectName,
			SubjectDigest: attestation.SubjectDigest{
				Digest: sqlcSubject.SubjectDigest,
			},
		})
	}
}

// StoreAttestation adds an attestation to the MySQL database with a provided transaction
func (d *LiveDatabase) StoreAttestation(ctx context.Context, attestation *attestation.Record, tx *sql.Tx) (uint64, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_StoreAttestation")
	defer span.End()

	// cast to sqlc type
	a, err := toSQLC(attestation)
	if err != nil {
		return 0, &ErrConvertToSQLC{err}
	}

	// store in database
	// create a new timer to capture the duration it takes to store the attestation record in MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	qtx := sqlc.New(tx)
	sqlResult, err := qtx.StoreAttestation(ctx, a)

	if err != nil {
		d.logger.Info("Failed to store attestation record in MySQL", kvp.Uint64("Record-ID", attestation.ID), kvp.String("Domain", "GitHub"))

		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToStoreRecord, nil, 1)

		return 0, &ErrStoreRecord{err}
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
		return 0, &ErrStoreRecord{err}
	}

	return castToUInt64(idInt64), nil
}

/*
	Helper functions
*/

// NOTE: this function will be removed in a followup, see https://github.com/github/package-security/issues/2486
// fromListAttestationsByOwnerSubjectDigestRow converts from the sqlc.ListAttestationsByOwnerSubjectDigestRow type to the attestation.Record type.
func fromListAttestationsByOwnerSubjectDigestRow(sqlcAttestation *sqlc.ListAttestationsByOwnerSubjectDigestRow) (attestation.Record, error) {
	var cert *x509.Certificate
	var err error

	// if the certificate is not empty, parse it
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

	// unmarshal the statement
	statement := &in_toto.Statement{}
	err = protojson.Unmarshal([]byte(sqlcAttestation.Statement), statement)
	if err != nil {
		return attestation.Record{}, fmt.Errorf("failed to unmarshal statement: %w", err)
	}

	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		DomainID:      sqlcAttestation.DomainID,
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		Certificate:   cert,
		MediaType:     sqlcAttestation.MediaType,
		PredicateType: sqlcAttestation.PredicateType,
		StatementType: sqlcAttestation.StatementType,
		Statement:     statement,
		CreatedAt:     sqlcAttestation.CreatedAt,
		SubjectName:   sqlcAttestation.SubjectName,
		SubjectDigest: sqlcAttestation.SubjectDigest,
		Subjects: []attestation.Subject{
			{
				Name: sqlcAttestation.SubjectName,
				SubjectDigest: attestation.SubjectDigest{
					Digest: sqlcAttestation.SubjectDigest,
				},
			},
		},
	}, nil
}

// NOTE: this function will be removed in a followup, see https://github.com/github/package-security/issues/2486
// convertListAttestationsByOwnerSubjectDigestRow converts from a collection of sqlc.ListAttestationsByOwnerSubjectDigestRow types to a collection of attestation.Record types.
func convertListAttestationsByOwnerSubjectDigestRow(sqlAttestations []sqlc.ListAttestationsByOwnerSubjectDigestRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i, sqlcAttestation := range sqlAttestations {
		record, err := fromListAttestationsByOwnerSubjectDigestRow(&sqlcAttestation)
		if err != nil {
			return nil, &ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = record
	}

	return attestations, nil
}

// fromListAttestationsByOwnerSubjectDigestsRow converts from the sqlc.ListAttestationsByOwnerSubjectDigestsRow type to the attestation.Record type.
func fromListAttestationsByOwnerSubjectDigestsRow(sqlcAttestation *sqlc.ListAttestationsByOwnerSubjectDigestsRow) (attestation.Record, error) {
	var cert *x509.Certificate
	var err error

	// if the certificate is not empty, parse it
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

	// unmarshal the statement
	statement := &in_toto.Statement{}
	err = protojson.Unmarshal([]byte(sqlcAttestation.Statement), statement)
	if err != nil {
		return attestation.Record{}, fmt.Errorf("failed to unmarshal statement: %w", err)
	}

	return attestation.Record{
		ID:            uint64(sqlcAttestation.ID),
		DomainID:      sqlcAttestation.DomainID,
		OwnerID:       convertToUInt64(sqlcAttestation.OwnerID),
		RepositoryID:  convertToUInt64(sqlcAttestation.RepositoryID),
		TenantID:      sqlcAttestation.TenantID,
		Certificate:   cert,
		MediaType:     sqlcAttestation.MediaType,
		PredicateType: sqlcAttestation.PredicateType,
		StatementType: sqlcAttestation.StatementType,
		Statement:     statement,
		CreatedAt:     sqlcAttestation.CreatedAt,
		SubjectName:   sqlcAttestation.SubjectName,
		SubjectDigest: sqlcAttestation.SubjectDigest,
		Subjects: []attestation.Subject{
			{
				Name: sqlcAttestation.SubjectName,
				SubjectDigest: attestation.SubjectDigest{
					Digest: sqlcAttestation.SubjectDigest,
				},
			},
		},
	}, nil
}

// convertListAttestationsByOwnerSubjectDigestRows converts from a collection of sqlc.ListAttestationsByOwnerSubjectDigestsRow types to a collection of attestation.Record types.
func convertListAttestationsByOwnerSubjectDigestsRow(sqlAttestations []sqlc.ListAttestationsByOwnerSubjectDigestsRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i, sqlcAttestation := range sqlAttestations {
		record, err := fromListAttestationsByOwnerSubjectDigestsRow(&sqlcAttestation)
		if err != nil {
			return nil, &ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = record
	}

	return attestations, nil
}
