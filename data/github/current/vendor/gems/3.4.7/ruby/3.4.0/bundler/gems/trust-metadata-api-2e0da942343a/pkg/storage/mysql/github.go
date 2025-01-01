package mysql

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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
	metricBatchFetchAttestationTime            = "mysql_attestation_batch_fetch_duration"
	metricFetchedCount                         = "mysql_fetched_record_count"
	metricFailedToDeleteRecordsByID            = "mysql_failed_to_delete_records_by_id"
	metricFailedToDeleteRecordsBySubjectDigest = "mysql_failed_to_delete_records_by_subject_digest"
)

/*
  GitHub API Queries
*/

// NOTE: this function will be removed in a followup, see https://github.com/github/package-security/issues/2486
// ListAttestationsByOwnerSubjectDigest retrieves the attestation from the MySQL database with given subject digest.
func (d *LiveDatabase) ListAttestationsByOwnerSubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *DescCursor) ([]attestation.Record, *attestation.PageInfo, error) {
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
func (d *LiveDatabase) ListAttestationsByOwnerSubjectDigests(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *DescCursor) ([]attestation.Record, *attestation.PageInfo, error) {
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
	d.logger.Info(fmt.Sprintf("Duration to fetch attestations by multiple subject digests in MySQL: %d us",
		fetchDurationTime.Microseconds()),
		kvp.String("Domain", "GitHub"))
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

func (d *LiveDatabase) ListBundleIdentifiersByAttestationID(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) ([]attestation.Record, error) {
	ctx, span := o11y.NamedSpan(ctx, "DB_ListBundleIdentifiersByAttestationID")
	defer span.End()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	params := sqlc.ListBundleIdentifiersByAttestationIdParams{
		AttestationIds: identifiers.AttestationIDs,
		DomainID:       identifiers.DomainID,
		OwnerID:        convertToSQLNullInt64(&identifiers.OwnerID),
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: 1024,
	}

	tx := sqlc.New(d.db)
	rows, err := tx.ListBundleIdentifiersByAttestationId(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, &ErrGetRecord{err}
	}
	if len(rows) == 0 {
		return nil, ErrAttestationNotFound
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration to fetch attestation records in MySQL: %d us",
		fetchDurationTime.Microseconds()),
		kvp.String("Domain", "GitHub"))

	records, err := convertListRepoIDsByAttestationIDRow(rows)
	if err != nil {
		return nil, &ErrGetRecord{err}
	}

	return records, nil
}

func (d *LiveDatabase) ListBundleIdentifiersBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) ([]attestation.Record, error) {
	ctx, span := o11y.NamedSpan(ctx, "DB_ListBundleIdentifiersBySubjectDigest")
	defer span.End()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	params := sqlc.ListBundleIdentifiersBySubjectDigestParams{
		SubjectDigests: identifiers.SubjectDigests,
		DomainID:       identifiers.DomainID,
		OwnerID:        convertToSQLNullInt64(&identifiers.OwnerID),
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: 1024,
	}

	tx := sqlc.New(d.db)
	rows, err := tx.ListBundleIdentifiersBySubjectDigest(ctx, params)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrAttestationNotFound
		}

		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, &ErrGetRecord{err}
	}
	if len(rows) == 0 {
		return nil, ErrAttestationNotFound
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration to fetch attestation records in MySQL: %d us",
		fetchDurationTime.Microseconds()),
		kvp.String("Domain", "GitHub"))

	records, err := convertListRepoIDsBySubjectDigestRow(rows)
	if err != nil {
		return nil, &ErrGetRecord{err}
	}

	return records, nil
}

// ListAttestationSummariesByRepository retrieves the attestation from the MySQL database with given subject digest.
func (d *LiveDatabase) ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor PageCursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_ListAttestationSummariesByRepository")
	defer span.End()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	after := cursor.GetAfter()
	before := cursor.GetBefore()
	params := sqlc.ListAttestationSummariesByRepositoryParams{
		After:        convertToSQLNullInt64(&after),
		Before:       convertToSQLNullInt64(&before),
		DomainID:     identifiers.DomainID,
		OwnerID:      convertToSQLNullInt64(identifiers.OwnerID),
		RepositoryID: convertToSQLNullInt64(identifiers.RepositoryID),
		// NOTE: due to a bug in sqlc, this parameter must name as Limit
		Limit: cursor.GetQueryLimit(),
		// NOTE: due to a bug in sqlc, this parameter must name as OrderBy
		OrderBy: cursor.GetFetchDirection(),
	}

	tx := sqlc.New(d.db)
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
	d.logger.Info(fmt.Sprintf("Duration to fetch attestation records in MySQL: %d us",
		fetchDurationTime.Microseconds()),
		kvp.String("Domain", "GitHub"))

	attestations, err := parseListAttestationSummariesByRepositoryRow(sqlAttestationsBatch)
	if err != nil {
		return nil, nil, &ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, attestations)
}

// ListAttestationSummariesByRepositoryWithFilters retrieves the attestation from the MySQL database with given subject digest.
func (d *LiveDatabase) ListAttestationSummariesByRepositoryWithFilters(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor PageCursor) ([]attestation.Record, *attestation.PageInfo, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_ListAttestationSummariesByRepositoryWithFilters")
	defer span.End()

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	values := []any{
		// required identifiers
		identifiers.DomainID,
		identifiers.OwnerID,
		identifiers.RepositoryID,
		// optional filters, must be provided twice
		// because the query checks if they are null or not
		identifiers.SubjectName,
		identifiers.SubjectName,
		identifiers.GetPredicateType(),
		identifiers.GetPredicateType(),
		identifiers.Created.GetOperator(),
		identifiers.Created.GetDate(),
		identifiers.Created.GetOperator(),
		identifiers.Created.GetDate(),
		identifiers.Created.GetOperator(),
		identifiers.Created.GetDate(),
		identifiers.Created.GetOperator(),
		identifiers.Created.GetDate(),
		// cursor parameters
		cursor.GetBefore(),
		cursor.GetBefore(),
		cursor.GetAfter(),
		cursor.GetAfter(),
		// sort direction
		cursor.GetFetchDirection(),
		cursor.GetFetchDirection(),
		// page limit
		cursor.GetQueryLimit(),
	}
	stmt, err := d.db.PrepareContext(ctx, listAttestationSummariesWithFilters)
	if err != nil {
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)
		return nil, nil, &ErrGetRecord{err}
	}
	defer stmt.Close()

	rows, err := stmt.QueryContext(ctx, values...)
	if err != nil {
		// if failed to retrieve attestation record from database: sql: no rows in result
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrAttestationNotFound
		}
		// if record fetch failed, increment the failed fetch metric
		d.metrics.Counter(metricFailedToFetchRecord, nil, 1)

		return nil, nil, &ErrGetRecord{err}
	}
	defer rows.Close()

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToFetchRecord, nil, 0)

	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_with_filters_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration to fetch attestation records with filters in MySQL: %d us",
		fetchDurationTime.Microseconds()),
		kvp.String("Domain", "GitHub"))

	records, err := convertRowsToRecords(rows)
	if err != nil {
		return nil, nil, &ErrGetRecord{err}
	}

	return calculatePageInfo(cursor, records)
}

func convertRowsToRecords(rows *sql.Rows) ([]attestation.Record, error) {
	var records []attestation.Record
	for rows.Next() {
		var r Row
		if err := rows.Scan(
			&r.ID,
			&r.Certificate,
			&r.CreatedAt,
			&r.DomainID,
			&r.OwnerID,
			&r.PredicateType,
			&r.RepositoryID,
			&r.TenantID,
			&r.TotalRows,
			&r.SubjectCount,
			&r.SubjectName,
		); err != nil {
			return nil, err
		}
		record, err := r.ToRecord()
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, nil
}

func (d *LiveDatabase) DeleteAttestationsByID(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error) {
	ctx, span := o11y.NamedSpan(ctx, "DB_DeleteAttestationsByID")
	defer span.End()

	params := sqlc.DeleteAttestationsByIdParams{
		AttestationIds: identifiers.AttestationIDs,
		DeletedAt:      convertToSQLNullTime(deletedAt),
		DomainID:       identifiers.DomainID,
		OwnerID:        convertToSQLNullInt64(&identifiers.OwnerID),
		RepositoryID:   convertToSQLNullInt64(identifiers.RepositoryID),
	}

	tx := sqlc.New(d.db)
	result, err := tx.DeleteAttestationsById(ctx, params)
	if err != nil {
		d.logger.Info("Failed to mark attestations as deleted", kvp.String("Domain", "GitHub"))
		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToDeleteRecordsByID, nil, 1)
		return nil, err
	}

	// Check if no rows were affected which indicates that the attestation was
	// either not found or has already been marked as deleted
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	if rowsAffected == 0 {
		return nil, ErrAttestationNotFound
	}

	// After the records have been successfully marked as deleted, fetch information
	// that will be included in the delete attestation audit log
	auditInfo, err := tx.GetHydroDeleteRecordInfoByID(ctx, identifiers.AttestationIDs)
	if err != nil {
		return nil, err
	}

	// Create records from the audit information and attestation_subjects table
	// These records will be used in the transport layer to create the delete
	// attestation audit logs
	records := make([]attestation.Record, len(auditInfo))
	for i, id := range identifiers.AttestationIDs {
		subjects, err := convertJSONRawMessageToSubjects(auditInfo[i].Subjects)
		if err != nil {
			return nil, err
		}

		cert, err := toX509Cert(auditInfo[i].Certificate)
		if err != nil {
			return nil, err
		}

		records[i] = attestation.Record{
			ID:            id,
			PredicateType: auditInfo[i].PredicateType,
			TenantID:      auditInfo[i].TenantID,
			OwnerID:       convertToUInt64(auditInfo[i].OwnerID),
			RepositoryID:  convertToUInt64(auditInfo[i].RepositoryID),
			Certificate:   cert,
			Subjects:      subjects,
		}
	}

	return records, nil
}

func (d *LiveDatabase) DeleteAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error) {
	ctx, span := o11y.NamedSpan(ctx, "DB_DeleteAttestationsBySubjectDigest")
	defer span.End()

	sqlNullDeletedAt := convertToSQLNullTime(deletedAt)
	params := sqlc.DeleteAttestationsBySubjectDigestParams{
		DeletedAt:      sqlNullDeletedAt,
		DomainID:       identifiers.DomainID,
		OwnerID:        convertToSQLNullInt64(&identifiers.OwnerID),
		RepositoryID:   convertToSQLNullInt64(identifiers.RepositoryID),
		SubjectDigests: identifiers.SubjectDigests,
	}

	tx := sqlc.New(d.db)
	result, err := tx.DeleteAttestationsBySubjectDigest(ctx, params)
	if err != nil {
		d.logger.Info("Failed to mark attestations as deleted", kvp.String("Domain", "GitHub"))
		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToDeleteRecordsBySubjectDigest, nil, 1)
		return nil, err
	}

	// Check if no rows were affected which indicates that the attestation was
	// either not found or has already been marked as deleted
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	if rowsAffected == 0 {
		return nil, ErrAttestationNotFound
	}

	// After the records have been successfully marked as deleted, fetch information
	// that will be included in the delete attestation audit log
	infoParams := sqlc.GetHydroDeleteRecordInfoByOwnerSubjectDigestParams{
		DomainID:       identifiers.DomainID,
		OwnerID:        convertToSQLNullInt64(&identifiers.OwnerID),
		SubjectDigests: identifiers.SubjectDigests,
	}
	auditInfo, err := tx.GetHydroDeleteRecordInfoByOwnerSubjectDigest(ctx, infoParams)
	if err != nil {
		return nil, err
	}

	// Create records from the audit information and attestation_subjects table
	// These records will be used in the transport layer to create the delete
	// attestation audit logs
	records := make([]attestation.Record, len(auditInfo))
	for i, info := range auditInfo {
		subjects, err := convertJSONRawMessageToSubjects(info.Subjects)
		if err != nil {
			return nil, err
		}

		cert, err := toX509Cert(info.Certificate)
		if err != nil {
			return nil, err
		}

		records[i] = attestation.Record{
			ID:            info.ID,
			PredicateType: auditInfo[i].PredicateType,
			TenantID:      auditInfo[i].TenantID,
			OwnerID:       convertToUInt64(auditInfo[i].OwnerID),
			RepositoryID:  convertToUInt64(auditInfo[i].RepositoryID),
			Certificate:   cert,
			Subjects:      subjects,
		}
	}

	return records, nil
}

/*
  GitHub Query Helper Functions
*/

// fromSQLCGetAttestationSummaryByRepositoryRow converts from the sqlc.fromSQLCGetAttestationSummaryByRepositoryRow type to the attestation.Record type.
func fromSQLCGetAttestationSummaryByRepositoryRow(sqlcAttestation *sqlc.GetAttestationSummaryByRepositoryRow) (attestation.Record, error) {
	cert, err := toX509Cert(sqlcAttestation.Certificate)
	if err != nil {
		return attestation.Record{}, err
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

type SQLSubject struct {
	Name   string `json:"name"`
	Digest string `json:"digest"`
}

func convertJSONRawMessageToSubjects(m json.RawMessage) ([]attestation.Subject, error) {
	b, err := m.MarshalJSON()
	if err != nil {
		return nil, err
	}

	var sqlSubjects []SQLSubject
	if err = json.Unmarshal(b, &sqlSubjects); err != nil {
		return nil, err
	}

	subjects := make([]attestation.Subject, len(sqlSubjects))
	for i, s := range sqlSubjects {
		algAndDigest := strings.Split(s.Digest, ":")
		s := attestation.Subject{
			Name: s.Name,
			SubjectDigest: attestation.SubjectDigest{
				Alg:    algAndDigest[0],
				Digest: algAndDigest[1],
			},
		}
		subjects[i] = s
	}
	return subjects, nil
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

	// capture the duration it takes to store the attestation record in MySQL
	// and send it to DataDog as a timing metric
	storeDurationTime := metricTimer.Time("attestation_record_stored_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration to store attestation record in MySQL: %d us",
		storeDurationTime.Microseconds()),
		kvp.Uint64("Record-ID", attestation.ID),
		kvp.String("Domain", "GitHub"))

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
	cert, err := toX509Cert(sqlcAttestation.Certificate)
	if err != nil {
		return attestation.Record{}, err
	}

	// unmarshal the statement
	statement := &in_toto.Statement{}
	err = protojson.Unmarshal([]byte(sqlcAttestation.Statement), statement)
	if err != nil {
		return attestation.Record{}, fmt.Errorf("failed to unmarshal statement: %w", err)
	}

	var signer = ""
	if sqlcAttestation.Signer.Valid {
		signer = sqlcAttestation.Signer.String
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
		Signer:        signer,
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
func fromListAttestationsByOwnerSubjectDigestsRow(row *sqlc.ListAttestationsByOwnerSubjectDigestsRow) (attestation.Record, error) {
	cert, err := toX509Cert(row.Certificate)
	if err != nil {
		return attestation.Record{}, err
	}

	// unmarshal the statement
	statement := &in_toto.Statement{}
	if err = protojson.Unmarshal([]byte(row.Statement), statement); err != nil {
		return attestation.Record{}, fmt.Errorf("failed to unmarshal statement: %w", err)
	}

	return attestation.Record{
		ID:            uint64(row.ID),
		DomainID:      row.DomainID,
		OwnerID:       convertToUInt64(row.OwnerID),
		RepositoryID:  convertToUInt64(row.RepositoryID),
		TenantID:      row.TenantID,
		Certificate:   cert,
		MediaType:     row.MediaType,
		PredicateType: row.PredicateType,
		StatementType: row.StatementType,
		Statement:     statement,
		CreatedAt:     row.CreatedAt,
		SubjectName:   row.SubjectName,
		SubjectDigest: row.SubjectDigest,
		Subjects: []attestation.Subject{
			{
				Name: row.SubjectName,
				SubjectDigest: attestation.SubjectDigest{
					Digest: row.SubjectDigest,
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

func convertListRepoIDsByAttestationIDRow(rows []sqlc.ListBundleIdentifiersByAttestationIdRow) ([]attestation.Record, error) {
	records := make([]attestation.Record, len(rows))
	for i, r := range rows {
		record := attestation.Record{
			ID:           r.ID,
			CreatedAt:    r.CreatedAt,
			OwnerID:      convertToUInt64(r.OwnerID),
			RepositoryID: convertToUInt64(r.RepositoryID),
		}
		records[i] = record
	}

	return records, nil
}

func convertListRepoIDsBySubjectDigestRow(rows []sqlc.ListBundleIdentifiersBySubjectDigestRow) ([]attestation.Record, error) {
	records := make([]attestation.Record, len(rows))
	for i, r := range rows {
		record := attestation.Record{
			CreatedAt:     r.CreatedAt,
			ID:            r.ID,
			OwnerID:       convertToUInt64(r.OwnerID),
			RepositoryID:  convertToUInt64(r.RepositoryID),
			SubjectDigest: r.SubjectDigest,
		}
		records[i] = record
	}

	return records, nil
}
