package notify

import (
	"encoding/json"

	authzdpb "github.com/github/authzd/pkg/proto"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/job/tracking"
)

const metricName string = "tracking_notify"
const topic = "tracking.notifyd.v0.Notify"

/*
NewTracker will:
  - Unmarshal the Notify message from the Request payload
  - Skip messages that are coming from retries
  - Scrub any sensitive and problematic data from that message so our analytics tooling can
    ingest it. That means removing references to internal types in fields holding `Any` types
    and replacing them with smaller types that live inside hydro-schemas.
  - Publish the final message to Hydro
*/
func NewTracker(telem *telemetry.Provider, statter stats.Client, publisher *hydropkg.Publisher) job.Handler {
	metered := hydro.NewMeteredPublisher(
		topic,
		metricName,
		publisher,
		metrics.NewPublisherMetrics(telem, statter),
	)

	return tracking.NewJobTracker(metricName, metered, filter, scrubRenderingField, scrubAuthzdAttributes)
}

// filter will return false if a message has retry attempts since these messages should not be tracked
func filter(msg *schemav0.Notify) (bool, string) {
	retriable := &retriables.Notify{Notify: msg}
	if retriable.GetAttempts() > 0 {
		return false, "the message has retry attempts"
	}

	return true, ""
}

// The Notify.Rendering field has attributes that use google's Any type.
// We need to make sure these are safe to ingest, that is, they hold references
// to hydro-schemas defined messages. We also want to remove sensitive data
// like email bodies, etc.
func scrubRenderingField(msg *schemav0.Notify) error {
	rendering := msg.GetRendering()
	if rendering == nil {
		return nil
	}

	if mobile := rendering.GetMobile(); mobile != nil {
		summary := entities.LayoutSummary{Kind: mobile.GetTypeUrl()}
		if anysummary, err := anypb.New(&summary); err == nil {
			rendering.Mobile = anysummary
		} else {
			rendering.Mobile = nil
		}
	}

	if email := rendering.GetEmail(); email != nil {
		summary := entities.LayoutSummary{Kind: email.GetTypeUrl()}
		if anysummary, err := anypb.New(&summary); err == nil {
			rendering.Email = anysummary
		} else {
			rendering.Email = nil
		}
	}

	return nil
}

// The Notify.Authorization.AuthzdAttributes field is a collection of Any types.
// These usually hold references to authzd's Attribute type, which can be a complex
// type not present in hydro-schemas. We want to simplify these attributes
// with a string representation of them for tracking purposes.
func scrubAuthzdAttributes(msg *schemav0.Notify) error {
	auth := msg.GetAuthorization()
	if auth == nil {
		return nil
	}

	attrs := auth.GetAuthzdAttributes()
	if attrs == nil {
		return nil
	}

	props := []*anypb.Any{}
	for _, wrapped := range attrs {
		var attr authzdpb.Attribute
		if err := proto.Unmarshal(wrapped.GetValue(), &attr); err != nil {
			continue
		}

		prop := entities.Attribute{
			Key:   attr.GetId(),
			Value: unwrapAuhtzdValue(attr.GetValue()),
		}

		if anyattr, err := anypb.New(&prop); err == nil {
			props = append(props, anyattr)
		}
	}

	msg.Authorization.AuthzdAttributes = props

	return nil
}

func unwrapAuhtzdValue(value *authzdpb.Value) string {
	switch valType := value.GetKind().(type) {
	case *authzdpb.Value_NullValue, nil:
		return "null"
	case *authzdpb.Value_BoolValue:
		return asString(valType.BoolValue)
	case *authzdpb.Value_IntegerValue:
		return asString(valType.IntegerValue)
	case *authzdpb.Value_DoubleValue:
		return asString(valType.DoubleValue)
	case *authzdpb.Value_StringValue:
		return valType.StringValue
	case *authzdpb.Value_IntegerListValue:
		return asString(valType.IntegerListValue.Values)
	case *authzdpb.Value_StringListValue:
		return asString(valType.StringListValue.Values)
	default:
		return "unknown"
	}
}

func asString(value any) string {
	b, err := json.Marshal(value)
	if err != nil {
		return "unknown"
	}

	return string(b)
}
