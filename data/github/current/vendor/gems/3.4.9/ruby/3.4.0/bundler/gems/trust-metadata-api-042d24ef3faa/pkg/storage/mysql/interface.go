package mysql

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

type Database interface {
	Close() error
	GetDB() *sql.DB
	StoreAttestationSubjects(context.Context, uint64, []attestation.Subject, *sql.Tx) error
	// NPM
	GetAttestationsByPurl(context.Context, attestation.IdentifiersNPM) ([]attestation.Record, error)
	GetAttestationByPurlPredicateType(context.Context, attestation.IdentifiersNPM, []string) (*attestation.Record, error)
	StoreNPMAttestation(context.Context, *attestation.Record, *sql.Tx) (uint64, error)
	// GitHub
	DeleteAttestationsByID(ctx context.Context, attestationIDs []uint64, deletedAt time.Time) error
	ListAttestationsByOwnerSubjectDigest(context.Context, attestation.IdentifiersGitHub, *Cursor) ([]attestation.Record, *attestation.PageInfo, error)
	ListAttestationsByOwnerSubjectDigests(context.Context, attestation.IdentifiersGitHub, *Cursor) ([]attestation.Record, *attestation.PageInfo, error)
	ListAttestationSummariesByRepository(context.Context, attestation.IdentifiersGitHub, *Cursor) ([]attestation.Record, *attestation.PageInfo, error)
	GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
	GetAttestationSummaryByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
	StoreAttestation(context.Context, *attestation.Record, *sql.Tx) (uint64, error)
	StoreRelease(context.Context, uint64, *attestation.Record, *sql.Tx) error
}
