package hydro

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// Utility functions for applying and extracting per-event coordinates
// to the current context.Context for use in observability in handlers

// KafkaEventCoordsKeyType is the context key type for storing Kafka event coordinates
type kafkaEventCoordsKeyType struct{}

// KafkaEventCoords holds basic hydro event coordinates for logging
type KafkaEventCoords struct {
	EventID    string
	Partition  int32
	Offset     int64
	Topic      string
	TenantID   string
	TenantName string
}

// Fields returns the kvp.Fields representation of the KafkaEventCoords
func (k KafkaEventCoords) Fields() []kvp.Field {
	fs := []kvp.Field{
		semconv.HydroDestinationPartitionID(k.Partition),
		semconv.HydroKafkaMessageOffset(k.Offset),
		semconv.HydroDestinationName(k.Topic),
	}
	if k.EventID != "" {
		fs = append(fs, semconv.HydroEventID(k.EventID))
	}
	if k.TenantName != "" {
		fs = append(fs, kvp.String("gh.tenant", k.TenantName))
	}
	if k.TenantID != "" {
		fs = append(fs, kvp.String("gh.tenant.id", k.TenantID))
	}

	return fs
}

// NewKafkaEventCoords stores basic hydro event coordinates from the hydro.Message into context
// Returns updated context and coords
func NewKafkaEventCoords(ctx context.Context, hm *hydro.Message) (context.Context, KafkaEventCoords) {
	coords := &KafkaEventCoords{
		Partition: hm.Partition,
		Offset:    hm.Offset,
		Topic:     hm.Topic,
	}

	// Multi-Tenancy in Proxima requires using tenant headers across services
	tenantName, ok := hm.Headers[headers.Tenant]
	if ok {
		ctx = tenant.TenantContext(ctx, tenantName)
		coords.TenantName = tenantName
	}

	tenantID, ok := hm.Headers[headers.TenantID]
	if ok {
		ctx = tenant.TenantIDContext(ctx, tenantID)
		coords.TenantID = tenantID
	}

	return context.WithValue(ctx, kafkaEventCoordsKeyType{}, coords), *coords
}

// KafkaEventCoordsWithEventID gets existing KafkaEventCoords from context and adds/overrides event ID from envelope
// Returns updated context and coords
func KafkaEventCoordsWithEventID(ctx context.Context, ev *hydroclient.Envelope) (context.Context, KafkaEventCoords) {
	coords, _ := ctx.Value(kafkaEventCoordsKeyType{}).(*KafkaEventCoords)
	if coords == nil {
		coords = &KafkaEventCoords{}
	}

	eventID := ev.GetId()
	if len(eventID) == 0 {
		eventID = requestid.NewGitHubRequestID()
	}
	coords.EventID = eventID

	// Update the context with the new event ID
	ctx = requestid.WithGitHubRequestID(ctx, eventID)

	// Store the updated coords back in context
	return context.WithValue(ctx, kafkaEventCoordsKeyType{}, coords), *coords
}

// GetKafkaEventCoords extracts Hydro event coordinates from context
// Returns coordinates or zero-value if not present
func GetKafkaEventCoords(ctx context.Context) KafkaEventCoords {
	coords, _ := ctx.Value(kafkaEventCoordsKeyType{}).(*KafkaEventCoords)
	if coords == nil {
		return KafkaEventCoords{}
	}
	return *coords
}
