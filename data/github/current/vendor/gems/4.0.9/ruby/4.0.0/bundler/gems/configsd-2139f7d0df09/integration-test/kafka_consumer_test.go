//go:build integration

package integrationtest

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/configsd/internal/fixtures"
	"github.com/github/configsd/internal/handlers"
	"github.com/github/configsd/internal/hydro"
	repositoriesv1 "github.com/github/configsd/internal/hydro/schemas/github/repositories/v1"
	"github.com/github/configsd/internal/hydro/schemas/github/v2/entities"
	"github.com/github/feature-management-client-go/vexi/v2"
	fakeAdapter "github.com/github/feature-management-client-go/vexi/v2/adapter/fake"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	testKafkaBroker   = "127.0.0.1:9092"
	testConsumerGroup = "configsd-integration-test"
	testTimeout       = 30 * time.Second
)

// TestKafkaConsumerIntegration tests the full Kafka consumer pipeline:
// 1. Produces a repository creation message to Kafka
// 2. Consumes the message using our consumer
// 3. Verifies the data was correctly stored in the database
func TestKafkaConsumerIntegration(t *testing.T) {
	// Setup test database using the fixtures package
	testDBConfig := fixtures.SetupDB(t, "configurations")

	// Execute test with database
	testDBConfig.ExecuteWithDBX(t, func(t *testing.T, dbConn *sqlx.DB) {
		ctx, cancel := context.WithTimeout(t.Context(), testTimeout)
		defer cancel()

		// Set environment variables for Kafka configuration using t.Setenv
		t.Setenv("KAFKA_BROKERS", testKafkaBroker)
		t.Setenv("KAFKA_GROUP", testConsumerGroup)

		// Test data
		testRepoID := uint64(12345)
		testOwnerID := uint64(67890)
		testRepoName := "test-repo"

		// Clean up any existing data
		cleanupTestData(t, dbConn, testRepoID)

		// Create and send test message to Kafka
		t.Log("Producing test message to Kafka...")
		if err := produceTestMessage(t, testRepoID, testOwnerID, testRepoName); err != nil {
			t.Skipf("Failed to produce test message - Kafka may not be available: %v", err)
		}

		adapter := fakeAdapter.NewFakeAdapter(false)
		adapter.AddFeatureFlag("configsd_persist_repo_owners", true)

		flagger, err := vexi.NewVexiClient(ctx, adapter, "configsd")
		if err != nil {
			t.Fatalf("Failed to create Vexi client: %v", err)
		}

		// Create consumer using NewConsumer with database dependency injection
		// All other config (server, Kafka settings) comes from environment
		consumer, err := hydro.NewConsumer(dbConn, flagger)
		if err != nil {
			t.Skipf("Kafka is not available - consumer creation failed: %v", err)
		}
		defer consumer.Close(ctx)

		// Setup consumer with a context that we can cancel
		consumerCtx, consumerCancel := context.WithCancel(ctx)

		// Start consuming in a goroutine
		consumeErr := make(chan error, 1)
		go func() {
			defer close(consumeErr)
			defer consumerCancel() // Ensure cancellation when done
			if err := consumer.ConsumeRepoCreationEvents(consumerCtx, consumerCancel); err != nil {
				select {
				case consumeErr <- err:
				default:
				}
			}
		}()

		// Wait for the message to be processed
		t.Log("Waiting for message to be processed...")

		var ownerID uint64
		maxAttempts := 10
		for attempts := 0; attempts < maxAttempts; attempts++ {
			// Query database directly to check if data was inserted
			err = dbConn.QueryRow("SELECT resource_owner_id FROM repository_owners WHERE repository_id = ?", testRepoID).Scan(&ownerID)
			if err == nil {
				break
			}
			if attempts == maxAttempts-1 {
				t.Fatalf("Failed to find repository owner after %d attempts: %v", maxAttempts, err)
			}
			time.Sleep(1 * time.Second)
		}

		// Cancel consumer context to stop consuming
		consumerCancel()

		// Verify the result
		assert.Equal(t, testOwnerID, ownerID, "Repository owner ID should match")

		t.Logf("Successfully processed Kafka message: repo_id=%d, owner_id=%d", testRepoID, ownerID)

		// Check for any consumer errors
		select {
		case err := <-consumeErr:
			// Context canceled is expected when we stop the consumer
			if err != nil && !errors.Is(err, context.Canceled) && err.Error() != "failed to consume messages: context canceled" {
				t.Errorf("Consumer error: %v", err)
			}
		case <-time.After(1 * time.Second):
			// No error received, which is good
		}
	})
}

// Helper functions

func cleanupTestData(t *testing.T, dbConn *sqlx.DB, repoID uint64) {
	_, err := dbConn.Exec("DELETE FROM repository_owners WHERE repository_id = ?", repoID)
	if err != nil {
		t.Logf("Warning: Failed to cleanup test data: %v", err)
	}
}

func createKafkaProducer() (sarama.SyncProducer, error) {
	config := sarama.NewConfig()
	config.Producer.Return.Successes = true
	config.Producer.Timeout = 10 * time.Second
	config.Producer.RequiredAcks = sarama.WaitForLocal // Less strict for kafka-lite
	config.Net.DialTimeout = 10 * time.Second
	config.Net.ReadTimeout = 10 * time.Second
	config.Net.WriteTimeout = 10 * time.Second
	config.Metadata.Timeout = 10 * time.Second
	config.Metadata.Retry.Max = 3
	config.Metadata.Retry.Backoff = 250 * time.Millisecond

	// Configure for compatibility with kafka-lite
	config.Version = sarama.V1_1_1_0

	producer, err := sarama.NewSyncProducer([]string{testKafkaBroker}, config)
	if err != nil {
		return nil, err
	}

	return producer, nil
}

func produceTestMessage(t *testing.T, repoID, ownerID uint64, repoName string) error {
	// Create test event
	event := &repositoriesv1.Created{
		RepositoryId: int64(repoID),
		Repository: &entities.Repository{
			Name:    repoName,
			OwnerId: wrapperspb.Int32(int32(ownerID)),
		},
	}

	data, err := proto.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal test event: %w", err)
	}

	producer, err := createKafkaProducer()
	if err != nil {
		return fmt.Errorf("failed to create Kafka producer: %w", err)
	}
	defer producer.Close()

	message := &sarama.ProducerMessage{
		Topic: handlers.RepoCreationHandlerTopic,
		Value: sarama.ByteEncoder(data),
	}

	partition, offset, err := producer.SendMessage(message)
	if err != nil {
		return fmt.Errorf("failed to send test message: %w", err)
	}

	t.Logf("Sent test message to partition %d, offset %d", partition, offset)
	return nil
}
