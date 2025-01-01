package payloads

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	"github.com/golang/snappy"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/pkg/payloads"
	"github.com/github/launch/types"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/asql"
)

var _ payloads.Store = (*DBStore)(nil)

// DBStore implements storage and retrieval of event payloads.
type DBStore struct {
	db     *asql.SQL
	logger logger.Logger
	stats  statter.Statter
}

// New returns an instance of the DBStore
func New(db *asql.SQL, log logger.Logger, stats statter.Statter) *DBStore {
	return &DBStore{
		db:     db,
		logger: log,
		stats:  stats,
	}
}

// Persist persists an event payload to the database.
func (s *DBStore) Persist(ctx context.Context, workflowBuildID int64, eventPayload []byte, _ types.GlobalID) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	mw.TagStatsWith(ctx, reqmeta.Tags{
		"error": "false",
	})

	const query = `INSERT INTO payloads (body, compression_type, created_at, workflow_build_id) VALUES (?, ?, ?, ?)`

	payload, compressionType := s.compressEventPayload(ctx, eventPayload)
	rows, err := s.db.ExecContextWith(ctx, query, asql.WithName("payloads.Persist"), payload, compressionType, time.Now().UTC(), workflowBuildID)
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return -1, tracing.RecordError(span, err)
	}

	id, err := rows.LastInsertId()
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return -1, tracing.RecordError(span, err)
	}

	return id, nil
}

func (s *DBStore) compressEventPayload(ctx context.Context, eventPayload []byte) ([]byte, CompressionType) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if eventPayload == nil {
		return nil, CompressionTypeNone
	}

	compressedPayload := snappy.Encode(nil, eventPayload)

	uncompressedSizeBytes := int64(len(eventPayload))
	compressedSizeBytes := int64(len(compressedPayload))

	span.AddEvent("event payload compression", trace.WithAttributes(
		attribute.Int64("gh.launch.event_payload.uncompressed_size", uncompressedSizeBytes),
		attribute.Int64("gh.launch.event_payload.compressed_size", compressedSizeBytes),
	))

	s.logger.Log(ctx, "finished event payload compression", kvp.Int64("gh.launch.event_payload.uncompressed_size", uncompressedSizeBytes), kvp.Int64("gh.launch.event_payload.compressed_size", compressedSizeBytes))
	if compressedSizeBytes > MaxMediumBlobSizeBytes {
		s.logger.Log(ctx, "skipping storage for oversized payload")
		return nil, CompressionTypeNone
	}

	return compressedPayload, CompressionTypeSnappy
}

// Get retrieves a payload with the specified workflow build ID.
func (s *DBStore) Get(ctx context.Context, workflowBuildID int64, _ types.GlobalID) ([]byte, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	mw.TagStatsWith(ctx, reqmeta.Tags{
		"error": "false",
	})

	query := `SELECT body, compression_type FROM payloads WHERE workflow_build_id = ? ORDER BY id LIMIT 1`

	rows, err := s.db.QueryContextWith(ctx, query, asql.WithName("payloads.Get"), workflowBuildID)
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return nil, tracing.RecordError(span, err)
	}

	defer rows.Close()

	if !rows.Next() {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return nil, tracing.RecordError(span, errors.New("no payload can be found for workflow build"))
	}
	if rows.Err() != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return nil, tracing.RecordError(span, rows.Err())
	}

	var compressedPayload []byte
	var compressionType CompressionType
	if err = rows.Scan(&compressedPayload, &compressionType); err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return nil, tracing.RecordError(span, err)
	}

	decompressedPayload, err := decompressEventPayload(compressedPayload, compressionType)
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"error": "true",
		})
		return nil, tracing.RecordError(span, err)
	}

	return decompressedPayload, nil
}

func decompressEventPayload(payload []byte, compressionType CompressionType) ([]byte, error) {
	if payload == nil {
		return nil, errors.New("missing payload")
	}

	if compressionType == CompressionTypeNone {
		return payload, nil
	}

	if compressionType == CompressionTypeSnappy {
		decompressedPayload, err := snappy.Decode(nil, payload)
		if err != nil {
			return nil, err
		}

		return decompressedPayload, nil
	}

	return nil, errors.New("unknown compression format")
}
