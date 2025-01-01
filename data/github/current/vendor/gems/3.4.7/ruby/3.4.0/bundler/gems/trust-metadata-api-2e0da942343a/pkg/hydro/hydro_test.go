package hydro

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	hydro_message_pb "github.com/github/trust-metadata-api/hydro/schemas/github/trust_metadata_api/v0"
	"github.com/github/trust-metadata-api/test/data"
	"google.golang.org/protobuf/proto"
)

func newMockHydroClient(sink *hydro.MemorySink) *Client {
	publisher, err := hydro.NewPublisher(sink)
	// create a mock logger

	if err != nil {
		return nil
	}

	logger, err := log.NewFromConfig(log.Config{
		Environment:        "testing",
		LogLevel:           log.DebugLevel.String(),
		LogConsoleEncoding: "logfmt",
	})

	if err != nil {
		return nil
	}

	return &Client{
		publisher: publisher,
		logger:    logger,
	}
}

func TestHydroPublishing(t *testing.T) {
	// The MemorySink writes events to a channel.
	events := make(chan hydro.Message, 100)
	sink, err := hydro.NewMemorySink(events)
	if err != nil {
		t.Fatal(err)
	}

	mockClient := newMockHydroClient(sink)
	bundle := data.SigstoreBundleWithMultipleSubjects(t)
	ownerID := uint64(101)
	repoID := uint64(202)
	tenantID := uint64(303)

	msg := CreateAttestationHydroMessage{
		bundle:   bundle,
		ownerID:  ownerID,
		repoID:   repoID,
		tenantID: tenantID,
	}

	mockClient.helperSendCreateAttestationHydroMessage(&msg)

	// Decode the Login event and assert that fields were set as expected.
	event := <-events

	envelope := hydro_pb.Envelope{}
	// nolint:errcheck
	proto.Unmarshal(event.Value, &envelope)

	message := hydro_message_pb.CreateAttestation{}
	// nolint:errcheck
	proto.Unmarshal(envelope.Message, &message)

	if message.WorkflowRunId != int64(11937918149) {
		t.Errorf("WorkflowRunId = %d, want %d", message.WorkflowRunId, uint(11937918149))
	}

	if message.OwnerId != safeCastUint64ToInt64(ownerID) {
		t.Errorf("OwnerId = %d, want %d", message.OwnerId, ownerID)
	}

	if message.RepositoryId != safeCastUint64ToInt64(repoID) {
		t.Errorf("RepositoryId = %d, want %d", message.RepositoryId, repoID)
	}

	if message.TenantId != safeCastUint64ToInt64(tenantID) {
		t.Errorf("TenantId = %d, want %d", message.TenantId, tenantID)
	}

	if message.SubjectName != "hello_linux_amd64" {
		t.Errorf("SubjectName = %s, want %s", message.SubjectName, "hello_linux_amd64")
	}

	if message.SubjectDigest != "sha256:c3bff36a5846508bddab3817da2e8423e74c8a8f49d87b453810eb17676e3098" {
		t.Errorf("SubjectDigest = %s, want %s", message.SubjectDigest, "sha256:c3bff36a5846508bddab3817da2e8423e74c8a8f49d87b453810eb17676e3098")
	}

	if message.AttestationType != "https://in-toto.io/Statement/v1" {
		t.Errorf("AttestationType = %s, want %s", message.AttestationType, "https://in-toto.io/Statement/v1")
	}

	if message.PredicateType != "https://slsa.dev/provenance/v1" {
		t.Errorf("PredicateType = %s, want %s", message.PredicateType, "https://slsa.dev/provenance/v1")
	}

	if message.SubjectsCount != 6 {
		t.Errorf("SubjectsCount = %d, want %d", message.SubjectsCount, 1)
	}

	b, _ := sgbundle.NewBundle(bundle)
	bundleData, _ := b.MarshalJSON()
	expectedSize := int64(len(bundleData))
	if message.AttestationSize != expectedSize {
		t.Errorf("AttestationSize = %d, want %d", message.AttestationSize, expectedSize)
	}
}
