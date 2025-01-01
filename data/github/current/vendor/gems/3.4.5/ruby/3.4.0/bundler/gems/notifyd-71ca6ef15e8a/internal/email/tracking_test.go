package email

import (
	context "context"
	"testing"
	"time"

	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	job "github.com/github/notifyd/internal/pkg/job/testhelper"
	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/github/notifyd/proto/layouts/email"
)

func Test_TrackerRun(t *testing.T) {
	ctx := context.Background()

	logger := log.NewNullLogger()
	telem := &telemetry.Provider{Logger: logger}
	statter := stats.NullStatter

	publisherChan := make(chan hydropkg.Message, 1)
	defer close(publisherChan)
	publisher, err := hydro.BuildMemoryPublisher(publisherChan)
	require.NoError(t, err)

	msg := &schemav0.DeliverEmail{
		LayoutData: getLayout(t),
		MatchData:  getTrackingMatchData(t),
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	var hydroPublishedMessage schemav0.DeliverEmail
	err = hydro.UnmarshalMessage(<-publisherChan, &hydroPublishedMessage)
	require.NoError(t, err)

	require.Contains(t, hydroPublishedMessage.LayoutData.GetTypeUrl(), "notifyd.v0.entities.LayoutSummary")
	require.Contains(t, hydroPublishedMessage.MatchData.GetTypeUrl(), "notifyd.v0.entities.MatchDataSummary")
}

func Test_TrackerRun_WithRetries(t *testing.T) {
	ctx := context.Background()

	logger := log.NewNullLogger()
	telem := &telemetry.Provider{Logger: logger}
	statter := stats.NullStatter

	publisherChan := make(chan hydropkg.Message, 1)
	defer close(publisherChan)
	publisher, err := hydro.BuildMemoryPublisher(publisherChan)
	require.NoError(t, err)

	msg := &schemav0.DeliverEmail{
		Retries: &entities.Retries{Attempts: 1},
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	require.Empty(t, publisherChan, "failure: the message was published into the tracking topic")
}

func Test_scrubLayoutData(t *testing.T) {
	msg := &schemav0.DeliverEmail{
		LayoutData: getLayout(t),
	}

	err := scrubLayoutData(msg)
	require.NoError(t, err)

	layout := msg.GetLayoutData()
	require.NotNil(t, layout)

	require.Equal(t, "type.googleapis.com/hydro.schemas.notifyd.v0.entities.LayoutSummary", layout.GetTypeUrl())
	var emailLayout entities.LayoutSummary
	err = proto.Unmarshal(layout.GetValue(), &emailLayout)
	require.NoError(t, err)
	require.Equal(t, "type.googleapis.com/notifyd.layouts.email.Basic", emailLayout.GetKind())
}

func Test_scrubMatchData(t *testing.T) {
	msg := &schemav0.DeliverEmail{
		MatchData: getTrackingMatchData(t),
	}

	err := scrubMatchData(msg)
	require.NoError(t, err)

	anyData := msg.GetMatchData()
	require.NotNil(t, anyData)
	summary := new(entities.MatchDataSummary)
	err = proto.Unmarshal(anyData.GetValue(), summary)
	require.NoError(t, err)

	count := 0
	for _, attr := range summary.Attributes {
		switch attr.GetKey() {
		// First level keys
		case "null":
			count++
			require.Equal(t, "null", attr.GetValue())
		case "number":
			count++
			require.Equal(t, "10", attr.GetValue())
		case "string":
			count++
			require.Equal(t, "test string", attr.GetValue())
		case "bool":
			count++
			require.Equal(t, "true", attr.GetValue())

		// Nested structs
		case "struct.string":
			count++
			require.Equal(t, "substring", attr.GetValue())
		case "struct.struct.string":
			count++
			require.Equal(t, "subsubstring", attr.GetValue())
		case "struct.list.0":
			count++
			require.Equal(t, "first", attr.GetValue())
		case "struct.list.1":
			count++
			require.Equal(t, "second", attr.GetValue())

		// Lists
		case "list.0":
			count++
			require.Equal(t, "first", attr.GetValue())
		case "list.1.number":
			count++
			require.Equal(t, "20", attr.GetValue())
		case "list.2":
			count++
			require.Equal(t, "30", attr.GetValue())
		}
	}

	require.Equal(t, 11, count, "there are untested attributes")
}

func getLayout(t *testing.T) *anypb.Any {
	t.Helper()

	basic := &email.Basic{
		Body: "this is a test",
	}

	return asAny(t, basic)
}

func getTrackingMatchData(t *testing.T) *anypb.Any {
	t.Helper()

	data, err := structpb.NewStruct(map[string]any{
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

	require.NoError(t, err)

	return asAny(t, data)
}

func asAny(t *testing.T, pb protoreflect.ProtoMessage) *anypb.Any {
	t.Helper()

	wrapped, err := anypb.New(pb)
	require.NoError(t, err)

	return wrapped
}
