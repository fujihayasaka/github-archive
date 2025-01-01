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
	"google.golang.org/protobuf/encoding/protojson"
)

const (
	metricFailedToStoreRecord = "mysql_attestation_record_store_fail_count"
	metricFailedToFetchRecord = "mysql_attestation_record_fetch_fail_count"
)

/*
  NPM API Queries
*/

// GetAttestationsByPurl retrieves the attestation from the MySQL database with a given purl and domain ID
func (d *LiveDatabase) GetAttestationsByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM) ([]attestation.Record, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationsByPurl")
	defer span.End()

	tx := sqlc.New(d.db)
	params := sqlc.GetAttestationsByPurlParams{
		Purl:     convertToSQLNullStr(identifiers.Purl),
		DomainID: uint32(identifiers.DomainID),
	}

	// create a new timer to capture the duration it takes to fetch multiple attestation records from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	sqlAttestations, err := tx.GetAttestationsByPurl(ctx, params)
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

	// capture the duration in milliseconds it takes to fetch attestation records from MySQL
	// and send it to DataDog as a timing metric
	fetchDurationTime := metricTimer.Time("multiple_attestation_records_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch multiple attestations record from MySQL: %d", fetchDurationTime), kvp.String("Purl", identifiers.Purl), kvp.String("Domain", "npm"))

	return convertGetAttestationsByPurlRowToAttestations(sqlAttestations)
}

// GetAttestationByPurlPredicateType retrieves the attestation from the MySQL database with a given purl, and predicate type
func (d *LiveDatabase) GetAttestationByPurlPredicateType(ctx context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_GetAttestationByPurlPredicateType")
	defer span.End()

	tx := sqlc.New(d.db)

	params := sqlc.GetAttestationByPurlPredicateTypeParams{
		Purl:           convertToSQLNullStr(identifiers.Purl),
		DomainID:       uint32(identifiers.DomainID),
		PredicateTypes: predicateTypes,
	}

	// create a new timer to capture the duration it takes to fetch an attestation record from MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	sqlAttestation, err := tx.GetAttestationByPurlPredicateType(ctx, params)
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

	// capture the duration in milliseconds it takes to fetch an attestation record from MySQL
	// and send it to DataDog as a timing metric
	fetchDurationTime := metricTimer.Time("attestation_record_fetch_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to fetch one attestation record from MySQL: %d", fetchDurationTime), kvp.Uint64("Record-ID", uint64(sqlAttestation.ID)), kvp.String("Purl", identifiers.Purl), kvp.String("Domain", "npm"))

	attestationRecord, err := fromSQLC(fromGetAttestationsByPurlPredicateTypeRowToSQLCAttestation(&sqlAttestation))

	if err != nil {
		return nil, &ErrConvertFromSQLC{err, sqlAttestation.ID}
	}

	return &attestationRecord, nil
}

// StoreNPMAttestation adds an attestation to the MySQL database for NPM records
// with a provided transaction
func (d *LiveDatabase) StoreNPMAttestation(ctx context.Context, attestation *attestation.Record, tx *sql.Tx) (uint64, error) {
	// set tracing for data layer
	ctx, span := o11y.NamedSpan(ctx, "DB_StoreNPMAttestation")
	defer span.End()

	// cast to sqlc type
	a, err := toSQLCStoreNPMAttestation(attestation)
	if err != nil {
		return 0, &ErrConvertToSQLC{err}
	}

	// store in database
	// create a new timer to capture the duration it takes to store the attestation record in MySQL
	// the duration will be sent to DataDog as a timing metric
	metricTimer := stats.NewTimer(d.metrics)

	qtx := sqlc.New(tx)
	sqlResult, err := qtx.StoreNPMAttestation(ctx, a)

	if err != nil {
		d.logger.Info("Failed to store attestation record in MySQL", kvp.Uint64("Record-ID", attestation.ID), kvp.String("Domain", "npm"))

		// if record storage failed, increment the failed store metric
		d.metrics.Counter(metricFailedToStoreRecord, nil, 1)

		return 0, &ErrStoreRecord{err}
	}

	// if record fetch succeeded, record zero to the failed fetch metric
	d.metrics.Counter(metricFailedToStoreRecord, nil, 0)

	// capture the duration in milliseconds it takes to store the attestation record in MySQL
	// and send it to DataDog as a timing metric
	storeDurationTime := metricTimer.Time("attestation_record_stored_duration", nil)
	d.logger.Info(fmt.Sprintf("Duration (MS) to store attestation record in MySQL: %d", storeDurationTime), kvp.Uint64("Record-ID", attestation.ID), kvp.String("Domain", "npm"))

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

// toSQLCStoreNPMAttestation converts from the attestation.Record type to the sqlc type for NPM records
func toSQLCStoreNPMAttestation(record *attestation.Record) (sqlc.StoreNPMAttestationParams, error) {
	var certB64 string

	stmtBytes, err := protojson.Marshal(record.Statement)
	if err != nil {
		return sqlc.StoreNPMAttestationParams{}, fmt.Errorf("failed to marshal statement from NPM: %w", err)
	}

	if record.Certificate != nil {
		certB64 = base64.StdEncoding.EncodeToString(record.Certificate.Raw)
	}

	domainID := uint32(record.DomainID)

	return sqlc.StoreNPMAttestationParams{
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

// fromSQLCGetAttestationsByPurlRow converts from the sqlc.GetAttestationsByPurlRow type to the attestation.Record type.
func fromSQLCGetAttestationsByPurlRow(sqlcAttestation *sqlc.GetAttestationsByPurlRow) (attestation.Record, error) {
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
		DomainID:      sqlcAttestation.DomainID,
		Purl:          sqlcAttestation.Purl.String,
		Certificate:   cert,
		PredicateType: sqlcAttestation.PredicateType,
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

// fromGetAttestationsByPurlPredicateTypeRowToSQLCAttestation converts from the sqlc.GetAttestationsByPurlPredicateTypeRow type to the sqlc.Attestation type.
func fromGetAttestationsByPurlPredicateTypeRowToSQLCAttestation(sqlcAttestation *sqlc.GetAttestationByPurlPredicateTypeRow) *sqlc.Attestation {
	return &sqlc.Attestation{
		ID:            sqlcAttestation.ID,
		DomainID:      sqlcAttestation.DomainID,
		Purl:          sqlcAttestation.Purl,
		Certificate:   sqlcAttestation.Certificate,
		MediaType:     sqlcAttestation.MediaType,
		PredicateType: sqlcAttestation.PredicateType,
		StatementType: sqlcAttestation.StatementType,
		Statement:     sqlcAttestation.Statement,
		CreatedAt:     sqlcAttestation.CreatedAt,
	}
}

// convertGetAttestationsByPurlRowToAttestations converts the collection of sqlc type to a collection of attestation.Record type
func convertGetAttestationsByPurlRowToAttestations(sqlAttestations []sqlc.GetAttestationsByPurlRow) ([]attestation.Record, error) {
	attestations := make([]attestation.Record, len(sqlAttestations))

	for i := range sqlAttestations {
		attestationRecord, err := fromSQLCGetAttestationsByPurlRow(&sqlAttestations[i])
		if err != nil {
			return nil, &ErrConvertFromSQLC{err, sqlAttestations[i].ID}
		}

		attestations[i] = attestationRecord
	}

	return attestations, nil
}
