// Package testpublisher provides testing utilities for the eventpublisher package.
//
// Example Usage:
//
//	func TestFooEventPublished(t *testing.T) {
//		tp := testpublisher.NewTestPublisher(t)
//		app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
//		require.NoError(t, err)
//
//		app.Subsystems.EventPublisher = tp.Publisher
//
//		foo := models.Foo{bar: "bar"}
//		app.Foo(foo)
//
//		expectedProto := &dependencygraphv1.Foo{bar: "bar"}
//
//		tp.AssertMessagePublished(t, "github.dependencygraph.v1.Foo", expectedProto)
//	}
package testpublisher

import (
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydro_base "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/google/go-cmp/cmp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"

	"github.com/github/osslicensecompliance/internal/eventpublisher"
)

// TestPublisher wraps an EventPublisher with testing utilities.
type TestPublisher struct {
	*eventpublisher.Publisher

	messageChan chan hydro.Message
}

// NewTestPublisher creates a new EventPublisher configured for testing.
// It uses a memory sink to capture published messages for verification.
func NewTestPublisher(t *testing.T) *TestPublisher {
	t.Helper()

	// Create a memory sink to capture published messages
	messageChan := make(chan hydro.Message, 10) // Buffer for multiple messages
	memorySink, err := hydro.NewMemorySink(messageChan)
	if err != nil {
		t.Fatalf("failed to create memory sink: %v", err)
	}

	publisher, err := hydro.NewPublisher(memorySink,
		hydro.WithTopicFormat(hydro.TopicFormatV2),
	)
	if err != nil {
		t.Fatalf("failed to create hydro publisher: %v", err)
	}
	ep, err := eventpublisher.NewNull(log.Named("test"), stats.NullStatter,
		eventpublisher.WithPublisher(publisher))
	if err != nil {
		t.Fatalf("failed to create event publisher: %v", err)
	}

	t.Cleanup(func() {
		err := ep.Close()
		if err != nil {
			t.Logf("failed to close event publisher: %v", err)
		}
	})

	return &TestPublisher{
		Publisher:   ep,
		messageChan: messageChan,
	}
}

// AssertMessagePublished verifies that a message with the expected topic and proto content was published.
func (tp *TestPublisher) AssertMessagePublished(t *testing.T, expectedTopic string, expectedProto proto.Message) {
	t.Helper()

	select {
	case message := <-tp.messageChan:
		// Verify topic
		if message.Topic != expectedTopic {
			t.Errorf("expected topic %q, got %q", expectedTopic, message.Topic)
			return
		}

		// Verify message has content
		if len(message.Value) == 0 {
			t.Error("message value should not be empty")
			return
		}

		// First unmarshal the Hydro envelope, then extract the actual message
		var env hydro_base.Envelope
		err := proto.Unmarshal(message.Value, &env)
		if err != nil {
			t.Errorf("Could not decode Hydro envelope: %v", err)
			return
		}

		// Clone the expected proto and clear it with reset
		// So we have an empty message to hydrate the actual message into
		actualProto := proto.Clone(expectedProto)
		proto.Reset(actualProto)

		err = proto.Unmarshal(env.Message, actualProto)
		if err != nil {
			t.Errorf("Could not decode proto message from envelope: %v", err)
			return
		}

		// Use protocmp for flexible protobuf comparison that handles slice ordering
		if diff := cmp.Diff(expectedProto, actualProto, protocmp.Transform()); diff != "" {
			t.Errorf("Proto messages are not equal (-expected +actual):\n%s", diff)
		}

	case <-time.After(1 * time.Second):
		t.Fatalf("expected message with topic %q was not published within timeout", expectedTopic)
	}
}

// AssertMessageTopic verifies that a message was published with the expected topic.
// This is useful when you only need to verify that an event was published,
// without verifying the message content.
func (tp *TestPublisher) AssertMessageTopic(t *testing.T, expectedTopic string) {
	t.Helper()

	select {
	case message := <-tp.messageChan:
		if message.Topic != expectedTopic {
			t.Errorf("expected topic %q, got %q", expectedTopic, message.Topic)
			return
		}
	case <-time.After(1 * time.Second):
		t.Fatalf("expected message with topic %q was not published within timeout", expectedTopic)
	}
}

// AssertNoMessagePublished verifies that no message was published within a short timeout.
// This is useful for testing error cases where publishing should not occur.
func (tp *TestPublisher) AssertNoMessagePublished(t *testing.T) {
	t.Helper()

	select {
	case message := <-tp.messageChan:
		t.Errorf("unexpected message published - Topic: %s, Size: %d bytes", message.Topic, len(message.Value))
	case <-time.After(100 * time.Millisecond):
		// Expected - no message should be published
	}
}

// SkipMessage consumes and discards the next message from the channel.
// This is useful when multiple events are published and you want to skip to a specific one.
func (tp *TestPublisher) SkipMessage(t *testing.T) {
	t.Helper()

	select {
	case <-tp.messageChan:
		// Message consumed and discarded
	case <-time.After(1 * time.Second):
		t.Fatal("expected a message to skip but none was published within timeout")
	}
}

// Close closes the test publisher and cleans up resources.
func (tp *TestPublisher) Close() error {
	if tp.Publisher != nil {
		return tp.Publisher.Close()
	}
	return nil
}
