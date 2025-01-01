package notify

import (
	"context"
	"testing"
	"time"

	authzdpb "github.com/github/authzd/pkg/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/anypb"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	job "github.com/github/notifyd/internal/pkg/job/testhelper"
	"github.com/github/notifyd/internal/pkg/tenancy"
	emailpkg "github.com/github/notifyd/proto/layouts/email"
	mobilepkg "github.com/github/notifyd/proto/layouts/mobile"
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

	mobile := getBasicMobileLayout(t)
	email := getBasicEmailLayout(t)
	attrs := getAuthzdAttributes(t)
	msg := &schemav0.Notify{
		Rendering: &schemav0.Notify_Rendering{
			Mobile: mobile,
			Email:  email,
		},
		Authorization: &schemav0.Notify_Authorization{
			AuthzdAttributes: attrs,
		},
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	var hydroPublishedMessage schemav0.Notify
	err = hydro.UnmarshalMessage(<-publisherChan, &hydroPublishedMessage)
	require.NoError(t, err)

	require.Contains(t, hydroPublishedMessage.Rendering.Mobile.GetTypeUrl(), "notifyd.v0.entities.LayoutSummary")
	require.Contains(t, hydroPublishedMessage.Rendering.Email.GetTypeUrl(), "notifyd.v0.entities.LayoutSummary")

	props := hydroPublishedMessage.Authorization.AuthzdAttributes
	require.Len(t, props, len(attrs))
	for _, prop := range props {
		require.Contains(t, prop.GetTypeUrl(), "notifyd.v0.entities.Attribute")
	}
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

	msg := &schemav0.Notify{
		Retries: &entities.Retries{Attempts: 1},
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	require.Empty(t, publisherChan, "failure: the message was published into the tracking topic")
}

func Test_scrubRenderingField(t *testing.T) {
	msg := &schemav0.Notify{
		Rendering: &schemav0.Notify_Rendering{
			Mobile: getBasicMobileLayout(t),
			Email:  getBasicEmailLayout(t),
		},
	}

	err := scrubRenderingField(msg)
	require.NoError(t, err)

	rendering := msg.GetRendering()
	require.NotNil(t, rendering)

	mobile := rendering.GetMobile()
	require.NotNil(t, mobile)
	require.Equal(t, "type.googleapis.com/hydro.schemas.notifyd.v0.entities.LayoutSummary", mobile.GetTypeUrl())
	var mobileLayout entities.LayoutSummary
	err = proto.Unmarshal(mobile.GetValue(), &mobileLayout)
	require.NoError(t, err)
	require.Equal(t, "type.googleapis.com/notifyd.layouts.mobile.Basic", mobileLayout.GetKind())

	email := rendering.GetEmail()
	require.NotNil(t, email)
	require.Equal(t, "type.googleapis.com/hydro.schemas.notifyd.v0.entities.LayoutSummary", email.GetTypeUrl())
	var emailLayout entities.LayoutSummary
	err = proto.Unmarshal(email.GetValue(), &emailLayout)
	require.NoError(t, err)
	require.Equal(t, "type.googleapis.com/notifyd.layouts.email.Basic", emailLayout.GetKind())
}

func Test_scrubAuthzdAttributes(t *testing.T) {
	original := getAuthzdAttributes(t)
	msg := &schemav0.Notify{
		Authorization: &schemav0.Notify_Authorization{
			AuthzdAttributes: original,
		},
	}

	err := scrubAuthzdAttributes(msg)
	require.NoError(t, err)

	auth := msg.GetAuthorization()
	require.NotNil(t, auth)
	attrs := auth.GetAuthzdAttributes()
	require.NotNil(t, attrs)

	count := 0
	for _, wrapped := range attrs {
		var prop entities.Attribute
		err := proto.Unmarshal(wrapped.GetValue(), &prop)
		require.NoError(t, err)

		count++

		switch prop.GetKey() {
		case "null":
			require.Equal(t, "null", prop.GetValue())
		case "bool":
			require.Equal(t, "true", prop.GetValue())
		case "int":
			require.Equal(t, "10", prop.GetValue())
		case "double":
			require.Equal(t, "10.5", prop.GetValue())
		case "string":
			require.Equal(t, "one", prop.GetValue())
		case "int-list":
			require.Equal(t, "[1,2,3]", prop.GetValue())
		case "string-list":
			require.Equal(t, "[\"one\",\"two\",\"three\"]", prop.GetValue())
		default:
			require.Fail(t, "attribute key unknown: %s", prop.GetKey())
		}
	}

	require.Equal(t, len(original), count)
}

func getAuthzdAttributes(t *testing.T) []*anypb.Any {
	t.Helper()

	attrs := []*anypb.Any{
		asAny(t, &authzdpb.Attribute{Id: "null", Value: authzdpb.NewNullValue()}),
		asAny(t, &authzdpb.Attribute{Id: "bool", Value: authzdpb.NewBoolValue(true)}),
		asAny(t, &authzdpb.Attribute{Id: "int", Value: authzdpb.NewInt64Value(10)}),
		asAny(t, &authzdpb.Attribute{Id: "double", Value: authzdpb.NewDoubleValue(10.5)}),
		asAny(t, &authzdpb.Attribute{Id: "string", Value: authzdpb.NewStringValue("one")}),
		asAny(t, &authzdpb.Attribute{Id: "int-list", Value: authzdpb.NewIntegerListValue(1, 2, 3)}),
		asAny(t, &authzdpb.Attribute{Id: "string-list", Value: authzdpb.NewStringListValue("one", "two", "three")}),
	}

	return attrs
}

func asAny(t *testing.T, pb protoreflect.ProtoMessage) *anypb.Any {
	t.Helper()

	wrapped, err := anypb.New(pb)
	require.NoError(t, err)

	return wrapped
}

func getBasicMobileLayout(t *testing.T) *anypb.Any {
	t.Helper()

	basic := &mobilepkg.Basic{
		Body: "this is a test",
	}

	return asAny(t, basic)
}

func getBasicEmailLayout(t *testing.T) *anypb.Any {
	t.Helper()

	basic := &emailpkg.Basic{
		Body: "this is a test",
	}

	return asAny(t, basic)
}
