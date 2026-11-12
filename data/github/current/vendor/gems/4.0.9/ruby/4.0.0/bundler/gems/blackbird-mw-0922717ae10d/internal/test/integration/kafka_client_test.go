package integration

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_CreateConsumerGroupWithCurrentEndOffsets(t *testing.T) {
	helpers.IntegrationTest(t)

	brokers := []string{"localhost:9092"}
	topic := fmt.Sprintf("test-%d", time.Now().UnixMilli())
	config := sarama.NewConfig()
	config.Version = sarama.V2_6_1_0
	config.Producer.Return.Successes = true
	config.Producer.Return.Errors = true
	config.Producer.RequiredAcks = sarama.WaitForAll
	client, err := sarama.NewClient(brokers, config)
	require.NoError(t, err)
	defer client.Close()

	makeAdminClient := func() sarama.ClusterAdmin {
		adminClient, err := sarama.NewClusterAdmin(brokers, config)
		if err != nil {
			panic("failed to create sarama cluster admin")
		}

		return adminClient
	}

	adminClient := kafka.NewAdminClient(makeAdminClient, client)
	defer adminClient.Close()
	clusterAdmin := makeAdminClient()
	defer clusterAdmin.Close()
	err = clusterAdmin.CreateTopic(topic, &sarama.TopicDetail{NumPartitions: 1, ReplicationFactor: 1}, false)
	require.NoError(t, err)

	// Create a new consumer group with end offsets on an empty topic. Should set offset to 0.
	cgManager := kafka.NewConsumerGroupManager(adminClient)
	cgID := fmt.Sprintf("test-cg-1-%d", time.Now().UnixMilli()) // using a per-test unique name make evaluating the output simpler
	err = cgManager.CreateWithEndOffsets(context.Background(), topic, cgID)
	require.NoError(t, err)

	offsets, err := clusterAdmin.ListConsumerGroupOffsets(cgID, map[string][]int32{topic: {0}})
	require.NoError(t, err)
	require.Equal(t, 1, len(offsets.Blocks))
	require.Equal(t, 1, len(offsets.Blocks[topic]))
	block := offsets.Blocks[topic][0]
	require.Equal(t, int64(0), block.Offset, "expect offset to be 0 when no message in topic")

	// Now, produce some messages
	producer, err := sarama.NewSyncProducer(brokers, config)
	require.NoError(t, err)
	partition, offset, err := producer.SendMessage(&sarama.ProducerMessage{
		Topic: topic,
		Value: sarama.StringEncoder("test 1"),
	})
	require.NoError(t, err)
	require.Equal(t, int32(0), partition)
	require.Equal(t, int64(0), offset)
	partition, offset, err = producer.SendMessage(&sarama.ProducerMessage{
		Topic: topic,
		Value: sarama.StringEncoder("test 2"),
	})
	require.NoError(t, err)
	require.Equal(t, int32(0), partition)
	require.Equal(t, int64(1), offset)
	err = producer.Close()
	require.NoError(t, err)

	// Create a new consumer group with end offsets on a topic with messages. Should set offset to 2(?).
	cgManager = kafka.NewConsumerGroupManager(adminClient)
	cgID = fmt.Sprintf("test-cg-2-%d", time.Now().UnixMilli()) // using a per-test unique name make evaluating the output simpler
	err = cgManager.CreateWithEndOffsets(context.Background(), topic, cgID)
	require.NoError(t, err)

	offsets, err = clusterAdmin.ListConsumerGroupOffsets(cgID, map[string][]int32{topic: {0}})
	require.NoError(t, err)
	require.Equal(t, 1, len(offsets.Blocks))
	require.Equal(t, 1, len(offsets.Blocks[topic]))
	block = offsets.Blocks[topic][0]
	require.Equal(t, int64(2), block.Offset, "expect offset to be 2 when two messages in topic")
}

// NOTE: This test relies on the onboard and incremental topics, created by bootstrap-kafka.
func Test_IsConsumerGroupPresentWithOffsets(t *testing.T) {
	helpers.IntegrationTest(t)
	ctx := context.Background()
	tc := routing.TopicConfig{
		Onboard: routing.OnboardTopicConfig{
			Partitions: 1,
		},
		Incremental: routing.IncrementalTopicConfig{
			Partitions: 1,
		},
	}

	brokers := []string{"localhost:9092"}
	config := sarama.NewConfig()
	config.Version = sarama.V2_6_1_0
	config.Producer.Return.Successes = true
	config.Producer.Return.Errors = true
	config.Producer.RequiredAcks = sarama.WaitForAll
	client, err := sarama.NewClient(brokers, config)
	require.NoError(t, err)
	defer client.Close()

	makeAdminClient := func() sarama.ClusterAdmin {
		adminClient, err := sarama.NewClusterAdmin(brokers, config)
		if err != nil {
			panic("failed to create sarama cluster admin")
		}

		return adminClient
	}

	adminClient := kafka.NewAdminClient(makeAdminClient, client)
	defer adminClient.Close()
	clusterAdmin := makeAdminClient()
	defer clusterAdmin.Close()

	cgID := fmt.Sprintf("test-cg-%d", time.Now().UnixMilli())

	// Consumer group should not be present because we haven't created it yet.
	present, err := adminClient.IsConsumerGroupPresent(cgID)
	require.NoError(t, err)
	require.False(t, present)
	present, err = adminClient.IsConsumerGroupPresentWithOffsets(ctx, cgID, tc)
	require.NoError(t, err)
	require.False(t, present)

	// Create a new consumer group with end offsets on an onboarding topic (but NOT incremental topic).
	cgManager := kafka.NewConsumerGroupManager(adminClient)
	err = cgManager.CreateWithEndOffsets(ctx, routing.OnboardSourceTopic, cgID)
	require.NoError(t, err)

	// IsConsumerGroupPresentWithOffsets should return false because incremental topic doesn't have offsets yet.
	// This is the important bit: it prevents locking the Kafka client because a consumer started using the offsets before we were done setting them.
	present, err = adminClient.IsConsumerGroupPresent(cgID)
	require.NoError(t, err)
	require.True(t, present, "expected consumer group to exist because we set offsets for one topic")
	present, err = adminClient.IsConsumerGroupPresentWithOffsets(ctx, cgID, tc)
	require.NoError(t, err)
	require.False(t, present, "expected consumer group to not exist because we haven't set offsets for ALL topics")

	// set offsets on the incremental topic
	err = cgManager.CreateWithEndOffsets(ctx, routing.IncrementalSourceTopic, cgID)
	require.NoError(t, err)

	// Now the consumer group should be present by both methods.
	present, err = adminClient.IsConsumerGroupPresent(cgID)
	require.NoError(t, err)
	require.True(t, present)
	present, err = adminClient.IsConsumerGroupPresentWithOffsets(ctx, cgID, tc)
	require.NoError(t, err)
	require.True(t, present)
}
