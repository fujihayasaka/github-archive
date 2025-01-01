//go:build db

package notifier

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/publisher"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/authnd/internal/tester"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	pbhydro "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/proto"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestJobE2E(t *testing.T) {
	ctx := commonTesting.NewLoggerContext(t)

	deadline, ok := t.Deadline()
	if !ok {
		deadline = time.Now().Add(10 * time.Second)
	}
	ctx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()

	store := testfixtures.CreateTestDatabaseStore(t, true)
	messages := make(chan hydro.Message, 100)
	job := newTestJob(t, store, messages)

	expectedMessages := []schema.ProgrammaticAccessEvent{
		{
			ActorId:               int64(testfixtures.RevokedProgrammaticAccessToken.ActorID),
			CredentialId:          int64(testfixtures.RevokedProgrammaticAccessToken.ID),
			AccessId:              int64(testfixtures.RevokedProgrammaticAccessToken.AccessID),
			CredentialSuffix:      string(testfixtures.RevokedProgrammaticAccessToken.TokenSuffix),
			CredentialIssuedAtUtc: timestamppb.New(testfixtures.Y2K),
			EventType:             schema.ProgrammaticAccessEvent_REVOKED,
			EventReason:           revokedNotificationReason,
			CatalogService:        serviceName,
			RequestId:             JobID,
			SendNotification:      false,
		},
		{
			ActorId:                int64(testfixtures.MonalisaProgrammaticAccessToken.ActorID),
			CredentialId:           int64(testfixtures.MonalisaProgrammaticAccessToken.ID),
			AccessId:               int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID),
			CredentialSuffix:       string(testfixtures.MonalisaProgrammaticAccessToken.TokenSuffix),
			CredentialExpiresAtUtc: timestamppb.New(testfixtures.SixDaysFromNow),
			CredentialIssuedAtUtc:  timestamppb.New(testfixtures.OneHundredHoursAgo),
			EventType:              schema.ProgrammaticAccessEvent_ISSUED,
			CatalogService:         serviceName,
			RequestId:              JobID,
			SendNotification:       true,
		},
		{
			ActorId:                int64(testfixtures.ExpiredProgrammaticAccessToken.ActorID),
			CredentialId:           int64(testfixtures.ExpiredProgrammaticAccessToken.ID),
			AccessId:               int64(testfixtures.ExpiredProgrammaticAccessToken.AccessID),
			CredentialSuffix:       string(testfixtures.ExpiredProgrammaticAccessToken.TokenSuffix),
			CredentialExpiresAtUtc: timestamppb.New(testfixtures.Y2KPlus),
			CredentialIssuedAtUtc:  timestamppb.New(testfixtures.Y2K),
			EventType:              schema.ProgrammaticAccessEvent_EXPIRED,
			CatalogService:         serviceName,
			RequestId:              JobID,
			SendNotification:       true,
		},
		{
			ActorId:                int64(testfixtures.ExpiringInTwentyThreeHoursProgrammaticAccessToken.ActorID),
			CredentialId:           int64(testfixtures.ExpiringInTwentyThreeHoursProgrammaticAccessToken.ID),
			AccessId:               int64(testfixtures.ExpiringInTwentyThreeHoursProgrammaticAccessToken.AccessID),
			CredentialSuffix:       string(testfixtures.ExpiringInTwentyThreeHoursProgrammaticAccessToken.TokenSuffix),
			CredentialExpiresAtUtc: timestamppb.New(testfixtures.TwentyThreeHoursFromNow),
			CredentialIssuedAtUtc:  timestamppb.New(testfixtures.OneHundredHoursAgo),
			EventType:              schema.ProgrammaticAccessEvent_EXPIRATION_WARNING,
			EventReason:            "1d",
			CatalogService:         serviceName,
			RequestId:              JobID,
			SendNotification:       true,
		},
		{
			ActorId:                int64(testfixtures.ExpiringIn6DaysProgrammaticAccessToken.ActorID),
			CredentialId:           int64(testfixtures.ExpiringIn6DaysProgrammaticAccessToken.ID),
			AccessId:               int64(testfixtures.ExpiringIn6DaysProgrammaticAccessToken.AccessID),
			CredentialSuffix:       string(testfixtures.ExpiringIn6DaysProgrammaticAccessToken.TokenSuffix),
			CredentialExpiresAtUtc: timestamppb.New(testfixtures.SixDaysFromNow),
			CredentialIssuedAtUtc:  timestamppb.New(testfixtures.OneHundredHoursAgo),
			EventType:              schema.ProgrammaticAccessEvent_EXPIRATION_WARNING,
			EventReason:            "7d",
			CatalogService:         serviceName,
			RequestId:              JobID,
			SendNotification:       true,
		},
	}
	if commonTesting.IsProximaMode() {
		for _, message := range expectedMessages {
			message.TenantId = testfixtures.DefaultBusiness.ID
		}
	}

	err := job.Run(ctx)
	assert.NoError(t, err)
	close(messages)

	assertHydroMessages(t, ctx, messages, expectedMessages)
}

func TestJobE2E_ExitsOnDeadline(t *testing.T) {
	ctx := commonTesting.NewLoggerContext(t)

	ctx, cancel := context.WithCancel(ctx)

	store := testfixtures.CreateTestDatabaseStore(t, true)
	messages := make(chan hydro.Message, 100)
	job := newTestJob(t, store, messages)

	expectedMessages := []schema.ProgrammaticAccessEvent{}

	// immediately cancel the context to simulate a shutdown signal
	cancel()

	err := job.Run(ctx)
	assert.NoError(t, err)
	close(messages)

	assertHydroMessages(t, ctx, messages, expectedMessages)
}

func assertHydroMessages(t *testing.T, ctx context.Context, messageChan <-chan hydro.Message, expectedEvents []schema.ProgrammaticAccessEvent) {
	t.Helper()

	numExpected := len(expectedEvents)
	var read int
	for {
		read++
		if len(expectedEvents) == 0 {
			// no more expected messages to read
			msg, ok := <-messageChan
			if ok {
				event, err := unwrapHydroMessage(t, msg)
				assert.NoError(t, err)
				t.Fatalf("observed unexpected extra hydro message: %+v", event)
			}
			return
		}
		expectedEvent := expectedEvents[0]
		expectedEvents = expectedEvents[1:]

		select {
		case <-ctx.Done():
			t.Fatalf("[%d/%d] test timed out waiting on hydro message", read, numExpected)

		case message, ok := <-messageChan:
			if !ok {
				if len(expectedEvents) > 0 {
					t.Logf("missing %d expected hydro events", len(expectedEvents))
					for ix, event := range expectedEvents {
						t.Logf("event[%d] = %+v", ix, event)
					}
					t.Fail()
				}
			}

			assert.Equal(t, "authnd.credential.development.v0.ProgrammaticAccess.Event", message.Topic)

			event, err := unwrapHydroMessage(t, message)
			require.NoError(t, err)

			// handle comparison of times explicitly to allow for slight deviations in processing time
			assert.InDelta(t, expectedEvent.CredentialIssuedAtUtc.Seconds, event.CredentialIssuedAtUtc.Seconds, 2)
			expectedEvent.CredentialIssuedAtUtc, event.CredentialIssuedAtUtc = nil, nil

			if event.CredentialExpiresAtUtc.IsValid() {
				assert.InDelta(t, expectedEvent.CredentialExpiresAtUtc.Seconds, event.CredentialExpiresAtUtc.Seconds, 2)
				expectedEvent.CredentialExpiresAtUtc, event.CredentialExpiresAtUtc = nil, nil
			}

			assert.Equal(t, expectedEvent, event)
		}
	}
}

func unwrapHydroMessage(t *testing.T, message hydro.Message) (schema.ProgrammaticAccessEvent, error) {
	t.Helper()

	var event schema.ProgrammaticAccessEvent
	var envelope pbhydro.Envelope
	err := proto.Unmarshal(message.Value, &envelope)
	if err != nil {
		return event, errors.Wrap(err, "failed to unmarshall message to hydro envelope")
	}

	err = proto.Unmarshal(envelope.Message, &event)
	if err != nil {
		return event, errors.Wrap(err, "failed to unmarshall envelope to prat event")
	}
	return event, nil
}

// creates a job wired up to a local kafka instance
func newTestJob(t *testing.T, store store.ProgrammaticAccessTokensStore, messages chan hydro.Message) *Job {
	t.Helper()

	provider, err := db.NewProvider(nil, nil, log.NewNullLogger(), stats.NullStatter)
	require.NoError(t, err)

	return &Job{
		statsDuration:    10 * time.Millisecond,
		statter:          stats.NullStatter,
		databaseProvider: provider,
		store:            store,
		publisher:        createIntegrationTestEventPublisher(t, messages),
	}
}

// creates an in-memory hydro source for integration testing
func createIntegrationTestEventPublisher(t *testing.T, messages chan hydro.Message) publisher.PratEventPublisher {
	cfg, err := tester.NewConfigFromEnvironment()
	require.NoError(t, err)

	if messages == nil {
		messages = make(chan hydro.Message, 10)
	}
	memorySink, err := hydro.NewMemorySink(messages)
	require.NoError(t, err)

	publisher, err := publisher.NewPratEventPublisher(
		context.Background(),
		&cfg.CommonConfig,
		func(kafka hydro.KafkaConfig) (hydro.Sink, error) { return memorySink, nil },
	)
	require.NoError(t, err)
	return publisher
}
