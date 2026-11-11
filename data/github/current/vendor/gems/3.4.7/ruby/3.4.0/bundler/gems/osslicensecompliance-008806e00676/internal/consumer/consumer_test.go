package consumer_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-stats"
	hydro_base "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	dgproto "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/consumer"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Consumer intergraion tests
//
// These tests check the integration of the consumer with a real Kafka broker.
// To ensure topic is received and errors are not returned to hydro
func TestConsumer_MessageHandleUnknownTopic_NoError(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	app, _ := testhelpers.SetupPolicy(t, testhelpers.RandomIDForDatabase(), testhelpers.RandomIDForDatabase(),
		"MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	cfg := &config.Config{
		HydroKafkaBrokers: "localhost:9092",
		KafkaClientID:     fmt.Sprintf("test-consumer-unknown-topic-%d", time.Now().UnixNano()),
		Environment:       "development",
	}
	statter := &stats.NullClient{}

	c, err := consumer.New(cfg, statter, app)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	t.Cleanup(cancel)

	consumeErr := make(chan error, 1)
	go func() {
		consumeErr <- c.Consume(ctx)
	}()

	time.Sleep(2 * time.Second)

	sendTestMessage(t, "github.dependencygraph.v1.UnknownTopic", nil)

	time.Sleep(3 * time.Second)

	cancel()

	select {
	case err := <-consumeErr:
		if err != nil && !errors.Is(err, context.Canceled) {
			t.Errorf("Consumer should not error on unknown topics, got: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Error("Consumer did not stop in time")
	}
}

// Integration test that tests happy path of SnapshotProcessed
func TestConsumerHandleSnapshotProcessed(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "test-commit-sha-123"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: testhelpers.PR42AsUint32,
		BaseSHA:           "base-sha",
		CommitSHA:         commitSHA,
		Status:            models.Waiting,
		ExpectedSnapshots: 3,
		ReceivedSnapshots: 2,
	})
	require.NoError(t, err)
	require.Equal(t, models.Waiting, checkJob.Status)

	cfg := &config.Config{
		HydroKafkaBrokers: "localhost:9092",
		KafkaClientID:     fmt.Sprintf("test-consumer-waiting-checkjob-%d", time.Now().UnixNano()),
		Environment:       "development",
	}
	statter := &stats.NullClient{}

	c, err := consumer.New(cfg, statter, app)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	t.Cleanup(cancel)

	consumeErr := make(chan error, 1)
	go func() {
		consumeErr <- c.Consume(ctx)
	}()

	time.Sleep(2 * time.Second)

	message := &dgproto.SnapshotProcessed{
		RepositoryId: int64(repoID),
		SnapshotId:   123456,
		Ref:          []byte("refs/heads/main"),
		Sha:          commitSHA,
		DetectorName: "test-detector",
		CreatedAt:    timestamppb.New(time.Now()),
		ScannedAt:    timestamppb.New(time.Now()),
	}
	sendTestMessage(t, "github.dependencygraph.v1.SnapshotProcessed", message)

	time.Sleep(3 * time.Second)

	updatedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedCheckJob)

	assert.Equal(t, models.Pass, updatedCheckJob.Status)
	assert.NotEqual(t, models.Waiting, updatedCheckJob.Status)

	cancel()

	select {
	case err := <-consumeErr:
		if err != nil && !errors.Is(err, context.Canceled) {
			t.Errorf("Consumer should not error when processing snapshot, got: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Error("Consumer did not stop in time")
	}
}

// HandleSnapshotProcessed tests
//
// These tests call the handler func directly without having to have kafka setup
// in the tests. So we can test in more granularity and run faster.
func TestHandleSnapshotProcessed_NoCheckJobExists_NoError(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	commitSHA := "test-commit-sha-no-checkjob"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)
	c := setupTestConsumer(t, app, "test-consumer-no-checkjob")
	message := createSnapshotMessage(t, repoID, commitSHA)

	err := c.HandleSnapshotProcessed(t.Context(), message)
	require.NoError(t, err)

	checkJob, err := app.Subsystems.Storage.GetCheckJobByCommit(t.Context(), repoID, commitSHA)
	require.NoError(t, err)
	assert.Nil(t, checkJob)
}

func TestHandleSnapshotProcessed_ValidationError_NoError(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "test-commit-sha-validation-error"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	// Create check job with invalid pull_request_number to trigger validation error
	createTestCheckJob(t, app, orgID, repoID, pullRequestID, commitSHA, 0, models.Waiting)

	c := setupTestConsumer(t, app, "test-consumer-validation-error")
	message := createSnapshotMessage(t, repoID, commitSHA)

	err := c.HandleSnapshotProcessed(t.Context(), message)
	require.NoError(t, err, "HandleSnapshotProcessed should not return error even when validation fails")

	unchangedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, 0)
	require.NoError(t, err)
	require.NotNil(t, unchangedCheckJob)
	assert.Equal(t, models.Waiting, unchangedCheckJob.Status, "check job status should remain unchanged due to validation error")
}

func TestHandleSnapshotProcessed_StorageError_ReturnsError(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "test-commit-sha-storage-error"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	createTestCheckJob(t, app, orgID, repoID, pullRequestID, commitSHA, testhelpers.PR42AsUint32, models.Waiting)

	// Close the storage to cause a storage error during Process
	err := app.Subsystems.Storage.Close()
	require.NoError(t, err)

	c := setupTestConsumer(t, app, "test-consumer-storage-error")
	message := createSnapshotMessage(t, repoID, commitSHA)

	err = c.HandleSnapshotProcessed(t.Context(), message)
	require.Error(t, err, "HandleSnapshotProcessed should return error when storage fails to trigger retry")
	assert.Contains(t, err.Error(), "database is closed", "error should indicate storage failure")
}

func sendTestMessage(t *testing.T, topic string, message *dgproto.SnapshotProcessed) {
	t.Helper()
	cfg := sarama.NewConfig()
	cfg.Producer.Return.Successes = true
	cfg.Producer.RequiredAcks = sarama.WaitForAll
	cfg.Version = sarama.V1_1_1_0

	producer, err := sarama.NewSyncProducer([]string{"localhost:9092"}, cfg)
	require.NoError(t, err)
	t.Cleanup(func() { producer.Close() })

	data := []byte("test-message")

	if message != nil {
		messageBytes, err := proto.Marshal(message)
		require.NoError(t, err)
		envelope := &hydro_base.Envelope{
			Id:      "test-envelope-id",
			TypeUrl: "test.message",
			Message: messageBytes,
		}

		data, err = proto.Marshal(envelope)
		require.NoError(t, err)
	}

	msg := &sarama.ProducerMessage{
		Topic: topic,
		Value: sarama.ByteEncoder(data),
	}

	_, _, err = producer.SendMessage(msg)
	require.NoError(t, err)
}

func createSnapshotMessage(t *testing.T, repositoryID uint64, commitSHA string) hydro.Message {
	t.Helper()
	snapshotProcessed := &dgproto.SnapshotProcessed{
		RepositoryId: int64(repositoryID),
		SnapshotId:   123456,
		Ref:          []byte("refs/heads/main"),
		Sha:          commitSHA,
		DetectorName: "test-detector",
		CreatedAt:    timestamppb.New(time.Now()),
		ScannedAt:    timestamppb.New(time.Now()),
	}

	snapshotBytes, err := proto.Marshal(snapshotProcessed)
	require.NoError(t, err)

	envelope := &hydro_base.Envelope{
		Id:      "test-envelope-id",
		TypeUrl: "github.dependencygraph.v1.SnapshotProcessed",
		Message: snapshotBytes,
	}

	envelopeBytes, err := proto.Marshal(envelope)
	require.NoError(t, err)

	return hydro.Message{
		Topic: "github.dependencygraph.v1.SnapshotProcessed",
		Value: envelopeBytes,
	}
}

func setupTestConsumer(t *testing.T, app *application.Application, clientID string) *consumer.Consumer {
	t.Helper()
	cfg := &config.Config{
		HydroKafkaBrokers: "localhost:9092",
		KafkaClientID:     clientID,
		Environment:       "development",
	}
	statter := &stats.NullClient{}

	c, err := consumer.New(cfg, statter, app)
	require.NoError(t, err)
	return c
}

func createTestCheckJob(t *testing.T, app *application.Application, orgID, repoID, pullRequestID uint64, commitSHA string, pullRequestNumber uint32, status models.CheckStatus) *models.CheckJob {
	t.Helper()
	checkJob, err := app.Subsystems.Storage.CreateCheckJob(t.Context(), models.CheckJob{
		EnterpriseID:      nil,
		OrganizationID:    orgID,
		RepositoryID:      repoID,
		PullRequestID:     pullRequestID,
		PullRequestNumber: pullRequestNumber,
		BaseSHA:           "base-sha",
		CommitSHA:         commitSHA,
		Status:            status,
		ExpectedSnapshots: 3,
		ReceivedSnapshots: 2,
	})
	require.NoError(t, err)
	return checkJob
}
