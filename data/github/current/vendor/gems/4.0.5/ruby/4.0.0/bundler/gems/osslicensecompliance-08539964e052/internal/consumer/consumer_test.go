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
	env := createSnapshotEnvelope(t, repoID, commitSHA)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
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
	env := createSnapshotEnvelope(t, repoID, commitSHA)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err, "HandleSnapshotProcessed should not return error even when validation fails")

	changedCheckJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, 0)
	require.NoError(t, err)
	require.NotNil(t, changedCheckJob)
	assert.Equal(t, models.Error, changedCheckJob.Status, "check job status should be set to error due to validation error")
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
	env := createSnapshotEnvelope(t, repoID, commitSHA)

	err = c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
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
	t.Cleanup(func() {
		err := producer.Close()
		if err != nil {
			t.Logf("failed to close producer: %v", err)
		}
	})

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

func createSnapshotEnvelope(t *testing.T, repositoryID uint64, commitSHA string) *hydro_base.Envelope {
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

	return &hydro_base.Envelope{
		Id:      "test-envelope-id",
		TypeUrl: "github.dependencygraph.v1.SnapshotProcessed",
		Message: snapshotBytes,
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

func createSnapshotEnvelopeWithRef(t *testing.T, repositoryID uint64, commitSHA string, ref []byte, detectorName string) *hydro_base.Envelope {
	t.Helper()
	snapshotProcessed := &dgproto.SnapshotProcessed{
		RepositoryId: int64(repositoryID),
		SnapshotId:   123456,
		Ref:          ref,
		Sha:          commitSHA,
		DetectorName: detectorName,
		CreatedAt:    timestamppb.New(time.Now()),
		ScannedAt:    timestamppb.New(time.Now()),
	}

	snapshotBytes, err := proto.Marshal(snapshotProcessed)
	require.NoError(t, err)

	return &hydro_base.Envelope{
		Id:      "test-envelope-id",
		TypeUrl: "github.dependencygraph.v1.SnapshotProcessed",
		Message: snapshotBytes,
	}
}

// createTestCheckJobWithRefAndDependabot creates a CheckJob with the given headRef and dependabot_pending,
// then updates it to the desired status.
func createTestCheckJobWithRefAndDependabot(t *testing.T, app *application.Application, orgID, repoID, pullRequestID uint64, commitSHA string, pullRequestNumber uint32, status models.CheckStatus, headRef *string, dependabotPending bool) *models.CheckJob {
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
		HeadRef:           headRef,
		DependabotPending: dependabotPending,
	})
	require.NoError(t, err)
	// Update to set desired status and dependabot_pending (CreateCheckJob defaults to Starting)
	checkJob.Status = status
	checkJob.DependabotPending = dependabotPending
	err = app.Subsystems.Storage.UpdateCheckJob(t.Context(), checkJob)
	require.NoError(t, err)
	return checkJob
}

func strPtr(s string) *string {
	return &s
}

func setupTestConsumerForTest(t *testing.T, app *application.Application) *consumer.Consumer {
	t.Helper()
	return consumer.NewForTest(app, &stats.NullClient{})
}

// --- Ref-based wakeup tests ---

func TestHandleSnapshotProcessed_SHAMatchOnly_RefPathDoesNotRun(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "sha-match-only"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", commitSHA, nil)

	// Create a Waiting CheckJob matched by SHA, no ref on event
	createTestCheckJob(t, app, orgID, repoID, pullRequestID, commitSHA, testhelpers.PR42AsUint32, models.Waiting)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, commitSHA, nil, "test-detector") // no ref, non-dependabot

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Job should have been woken (status changed from Waiting)
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.NotEqual(t, models.Waiting, updatedJob.Status, "SHA path should wake the job")
}

func TestHandleSnapshotProcessed_RefMatchOnly(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	eventSHA := "event-sha-no-match"
	jobSHA := "job-sha-different"
	ref := "refs/heads/feature"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", jobSHA, nil)

	// Create a Waiting + dependabot_pending CheckJob with head_ref, but different SHA than event
	createTestCheckJobWithRefAndDependabot(t, app, orgID, repoID, pullRequestID, jobSHA, testhelpers.PR42AsUint32, models.Waiting, strPtr(ref), true)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, eventSHA, []byte(ref), consumer.DependabotDetectorName)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Job should have been woken via the ref path
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.NotEqual(t, models.Waiting, updatedJob.Status, "ref path should wake the job")
}

func TestHandleSnapshotProcessed_BothPathsMatchSameJob_WokenOnce(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "both-match-sha"
	ref := "refs/heads/feature"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", commitSHA, nil)

	// Create a Waiting + dependabot_pending job matching both SHA and ref
	createTestCheckJobWithRefAndDependabot(t, app, orgID, repoID, pullRequestID, commitSHA, testhelpers.PR42AsUint32, models.Waiting, strPtr(ref), true)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, commitSHA, []byte(ref), consumer.DependabotDetectorName)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Job should be woken exactly once (no errors from double-waking)
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.NotEqual(t, models.Waiting, updatedJob.Status)
}

func TestHandleSnapshotProcessed_BothPathsMatchDifferentJobs(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID1 := testhelpers.RandomIDForDatabase()
	pullRequestID2 := testhelpers.RandomIDForDatabase()
	shaSHA := "sha-path-commit"
	refSHA := "ref-path-commit"
	ref := "refs/heads/feature"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", shaSHA, nil)

	// Job 1: matched by SHA only (no dependabot_pending, no head_ref)
	createTestCheckJob(t, app, orgID, repoID, pullRequestID1, shaSHA, 10, models.Waiting)

	// Job 2: matched by ref only (different SHA, dependabot_pending + head_ref)
	createTestCheckJobWithRefAndDependabot(t, app, orgID, repoID, pullRequestID2, refSHA, 11, models.Waiting, strPtr(ref), true)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, shaSHA, []byte(ref), consumer.DependabotDetectorName)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Both jobs should be woken
	job1, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, 10)
	require.NoError(t, err)
	assert.NotEqual(t, models.Waiting, job1.Status, "SHA-matched job should be woken")

	job2, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, 11)
	require.NoError(t, err)
	assert.NotEqual(t, models.Waiting, job2.Status, "ref-matched job should be woken")
}

func TestHandleSnapshotProcessed_NeitherPathMatches(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", "commit-sha", nil)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, "no-match-sha", []byte("refs/heads/no-match-ref"), consumer.DependabotDetectorName)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)
}

func TestHandleSnapshotProcessed_EmptyRef_RefPathSkipped(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "empty-ref-sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", commitSHA, nil)

	createTestCheckJob(t, app, orgID, repoID, pullRequestID, commitSHA, testhelpers.PR42AsUint32, models.Waiting)

	c := setupTestConsumerForTest(t, app)
	env := createSnapshotEnvelopeWithRef(t, repoID, commitSHA, nil, consumer.DependabotDetectorName) // empty ref

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// SHA path should still work
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.NotEqual(t, models.Waiting, updatedJob.Status)
}

func TestHandleSnapshotProcessed_DependabotPendingFalse_RefPathDoesNotMatchIt(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	commitSHA := "dependabot-false-sha"
	ref := "refs/heads/feature"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", commitSHA, nil)

	// Create a Waiting job with head_ref matching, but dependabot_pending = false
	createTestCheckJobWithRefAndDependabot(t, app, orgID, repoID, pullRequestID, commitSHA, testhelpers.PR42AsUint32, models.Waiting, strPtr(ref), false)

	c := setupTestConsumerForTest(t, app)
	// Use a SHA that WON'T match so we can observe ref-only behavior
	env := createSnapshotEnvelopeWithRef(t, repoID, "different-sha", []byte(ref), consumer.DependabotDetectorName)

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Job should NOT have been woken (ref path won't match dependabot_pending=false)
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.Equal(t, models.Waiting, updatedJob.Status, "ref path should not wake non-dependabot-pending jobs")
}

func TestHandleSnapshotProcessed_NonDependabotDetector_RefPathSkipped(t *testing.T) {
	orgID := testhelpers.RandomIDForDatabase()
	repoID := testhelpers.RandomIDForDatabase()
	pullRequestID := testhelpers.RandomIDForDatabase()
	ref := "refs/heads/feature"
	jobSHA := "non-dependabot-job-sha"

	app, _ := testhelpers.SetupPolicy(t, orgID, repoID, "MIT", "MIT", testhelpers.AllDistributionContexts, "base-sha", jobSHA, nil)

	// Create a Waiting + dependabot_pending job with matching ref
	createTestCheckJobWithRefAndDependabot(t, app, orgID, repoID, pullRequestID, jobSHA, testhelpers.PR42AsUint32, models.Waiting, strPtr(ref), true)

	c := setupTestConsumerForTest(t, app)
	// non-dependabot detector, different SHA, matching ref
	env := createSnapshotEnvelopeWithRef(t, repoID, "different-sha", []byte(ref), "pip")

	err := c.HandleSnapshotProcessed(t.Context(), app.Logger, env)
	require.NoError(t, err)

	// Job should NOT have been woken — ref path is skipped for non-dependabot detectors
	updatedJob, err := app.Subsystems.Storage.GetCheckJob(t.Context(), repoID, testhelpers.PR42AsUint32)
	require.NoError(t, err)
	require.NotNil(t, updatedJob)
	assert.Equal(t, models.Waiting, updatedJob.Status, "ref path should be skipped for non-dependabot detectors")
}
