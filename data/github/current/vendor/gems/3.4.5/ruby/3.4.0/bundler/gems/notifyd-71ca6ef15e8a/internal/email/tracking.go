package email

import (
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/job/tracking"
)

const metricName string = "tracking_deliver_email"
const topic = "tracking.notifyd.v0.DeliverEmail"

/*
NewTracker will:
  - Unmarshal the DeliverEmail message from the Request payload
  - Skip messages that are coming from retries
  - Scrub any sensitive and problematic data from that message so our analytics tooling can
    ingest it. That means removing references to internal types in fields holding `Any` types
    and replacing them with smaller types that live inside hydro-schemas.
  - Publish the final message to Hydro
*/
func NewTracker(
	telem *telemetry.Provider,
	statter stats.Client,
	publisher *hydropkg.Publisher,
) job.Handler {
	metered := hydro.NewMeteredPublisher(
		topic,
		metricName,
		publisher,
		metrics.NewPublisherMetrics(telem, statter),
	)

	return tracking.NewJobTracker(metricName, metered, filter, scrubLayoutData, scrubMatchData)
}

// filter will return false if a message has retry attempts since these messages should not be tracked
func filter(msg *schemav0.DeliverEmail) (bool, string) {
	retriable := &retriables.Email{DeliverEmail: msg}
	if retriable.GetAttempts() > 0 {
		return false, "the message has retry attempts"
	}

	return true, ""
}

// The DeliverEmail.LayoutData field is of google's Any type.
// We need to make sure this is safe to ingest, that is, it hold references
// to hydro-schemas defined messages. We also want to remove sensitive data.
func scrubLayoutData(msg *schemav0.DeliverEmail) error {
	layout := msg.GetLayoutData()
	if layout == nil {
		return nil
	}

	summary := entities.LayoutSummary{Kind: layout.GetTypeUrl()}
	if anysummary, err := anypb.New(&summary); err == nil {
		msg.LayoutData = anysummary
	} else {
		msg.LayoutData = nil
	}

	return nil
}

/*
The DeliverEmail.MatchData is a Struct with different nested data inside
Our ingestion analytics system can't deal well with structs of this kind,
so this method tries to flatten Struct data into a list of Attributes (a Key and Value pair).
The idea is to transform nested structures in a one dimensional List where each attribute's key
represents the path of that value inside the nested structure.

Example:

	// A struct with this form:
	data, _ := structpb.NewStruct(map[string]any{
		"null":   nil,
		"number": 10,
		"string": "test string",
		"bool":   true,

		"struct": map[string]any{
			"string": "substring",
			"struct": map[string]any{
				"string": "subsubstring",
			},
			"list": []any{"first", "second"},
		},

		"list": []any{
			"first",
			map[string]any{
				"number": 20,
			},
			30,
		},
	})

	// Will be flattened into this
	data := &entities.MatchDataSummary{Attributes: []*entities.Attribute{
		{ Key: "null", Value: "null"},
		{ Key: "number", Value: "10"},
		{ Key: "string", Value: "test string"},
		{ Key: "bool", Value: "true"},
		{ Key: "struct.string", Value: "substring"},
		{ Key: "struct.struct.string", Value: "subsubstring"},
		{ Key: "struct.list.0", Value: "first"},
		{ Key: "struct.list.1", Value: "second"},
		{ Key: "list.0", Value: "first"},
		{ Key: "list.1.number", Value: "20"},
		{ Key: "list.2", Value: "30"},
	}}
*/
func scrubMatchData(msg *schemav0.DeliverEmail) error {
	anyData := msg.GetMatchData()
	if anyData == nil {
		return nil
	}

	// Clean the data before trying to summarize it
	msg.MatchData = nil

	if !strings.Contains(anyData.GetTypeUrl(), ".Struct") {
		return nil
	}

	matchData := new(structpb.Struct)
	if err := proto.Unmarshal(anyData.GetValue(), matchData); err != nil {
		//nolint:nilerr // Here we are OK with doing nothing when this happens.
		return nil
	}

	if summary := flattenStruct(matchData); summary != nil {
		if anySummary, err := anypb.New(summary); err == nil {
			msg.MatchData = anySummary
		}
	}

	return nil
}

func flattenStruct(data *structpb.Struct) *entities.MatchDataSummary {
	attrs := []*entities.Attribute{}

	for key, value := range data.GetFields() {
		subattrs := flattenValue(key, value)
		attrs = append(attrs, subattrs...)
	}

	if len(attrs) == 0 {
		return nil
	}

	return &entities.MatchDataSummary{Attributes: attrs}
}

func flattenValue(key string, value *structpb.Value) []*entities.Attribute {
	switch v := value.GetKind().(type) {
	case *structpb.Value_NumberValue:
		if v != nil {
			return flattenNumberValue(key, value)
		}
	case *structpb.Value_StringValue:
		if v != nil {
			return flattenStringValue(key, value)
		}
	case *structpb.Value_BoolValue:
		if v != nil {
			return flattenBoolValue(key, value)
		}
	case *structpb.Value_NullValue:
		return flattenNullValue(key, value)
	case *structpb.Value_StructValue:
		if v != nil {
			return flattenStructValue(key, value)
		}
	case *structpb.Value_ListValue:
		if v != nil {
			return flattenListValue(key, value)
		}
	}

	return []*entities.Attribute{}
}

func flattenNumberValue(key string, value *structpb.Value) []*entities.Attribute {
	json, err := value.MarshalJSON()
	if err != nil {
		return []*entities.Attribute{}
	}

	return []*entities.Attribute{
		{Key: key, Value: string(json)},
	}
}

func flattenStringValue(key string, value *structpb.Value) []*entities.Attribute {
	return []*entities.Attribute{
		{Key: key, Value: value.GetStringValue()},
	}
}

func flattenBoolValue(key string, value *structpb.Value) []*entities.Attribute {
	str := "false"
	if value.GetBoolValue() {
		str = "true"
	}

	return []*entities.Attribute{
		{Key: key, Value: str},
	}
}

func flattenNullValue(key string, _ *structpb.Value) []*entities.Attribute {
	return []*entities.Attribute{
		{Key: key, Value: "null"},
	}
}

func flattenStructValue(key string, value *structpb.Value) []*entities.Attribute {
	attrs := []*entities.Attribute{}
	for subkey, subvalue := range value.GetStructValue().Fields {
		newKey := fmt.Sprintf("%s.%s", key, subkey)
		attrs = append(attrs, flattenValue(newKey, subvalue)...)
	}

	return attrs
}

func flattenListValue(key string, value *structpb.Value) []*entities.Attribute {
	attrs := []*entities.Attribute{}
	for idx, subvalue := range value.GetListValue().Values {
		newKey := fmt.Sprintf("%s.%d", key, idx)
		attrs = append(attrs, flattenValue(newKey, subvalue)...)
	}

	return attrs
}
