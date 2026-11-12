package kafka

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/IBM/sarama"
	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
)

// ConsumerGroupManager is an interface for managing consumer groups in Kafka. This interface is an overkill but mocking
// offset management using sarama library proved to be quite tedious and would require mocking all the way to broker
// abstraction in sarama. This interface is a compromise to make existing service tests easier to configure.
// Alternative would be to run some kind of in-memory kafka broker for tests which may be an overkill or even
// readily available.
type ConsumerGroupManager interface {
	// CreateConsumerGroup creates a new consumer group in kafka with the provided desired starting offsets.
	// Consumer group creation is a side effect of setting the partition offsets and then committing those.
	// Manual committing of offsets is important because we want to ensure that the offsets are committed atomically.
	// This ensures that the ingest process doesn't start processing incremental topics at the wrong point in time.
	// Manual committing works because the potomac kafka client does not auto commit offsets.
	Create(ctx context.Context, topic string, consumerGroup string, offsets map[int32]int64) error

	// CreateWithEndOffsets creates a new consumer group in kafka with the current end offsets for the given topic.
	// Similar to CreateConsumerGroup, the latest offsets are committed atomically.
	CreateWithEndOffsets(ctx context.Context, topic string, consumerGroup string) error
}
type consumerGroupManager struct {
	adminClient *AdminClient
}

func NewConsumerGroupManager(adminClient *AdminClient) ConsumerGroupManager {
	return &consumerGroupManager{
		adminClient: adminClient,
	}
}

func (c *consumerGroupManager) Create(ctx context.Context, topic string, consumerGroup string, offsets map[int32]int64) error {
	if len(offsets) == 0 {
		panic("empty offsets provided")
	}

	op := func() error {
		om, err := sarama.NewOffsetManagerFromClient(consumerGroup, c.adminClient.client)
		if err != nil {
			logging.Error(ctx, "error creating kafka offset manager, attempting to refresh controller", kvp.Err(err))
			c.refreshController(ctx)
			return fmt.Errorf("error creating kafka offset manager. topic: %s, consumer group: %s, %w", topic, consumerGroup, err)
		}
		defer om.Close()

		for partition, offset := range offsets {
			pm, err := om.ManagePartition(topic, partition)
			if err != nil {
				logging.Error(ctx, "error managing partition, attempting to refresh controller", kvp.Err(err))
				c.refreshController(ctx)
				return err
			}
			pm.MarkOffset(offset, "")
			if err := pm.Close(); err != nil {
				logging.Error(ctx, "error closing PartitionOffsetManager", kvp.Err(err))
				return err
			}
		}
		om.Commit()
		logging.Info(ctx, "created consumer group with offsets", kvp.String("topic", topic), kvp.String("consumer_group", consumerGroup), kvp.String("offsets", fmt.Sprintf("%+v", offsets)))
		return nil
	}

	return backoff.Retry(op, retry.DefaultBackOff(ctx, 10))
}

func (c consumerGroupManager) refreshController(ctx context.Context) {
	_, refreshErr := c.adminClient.client.RefreshController()
	if refreshErr != nil {
		logging.Error(ctx, "error calling RefreshController()", kvp.Err(refreshErr))
	}

}

func (c *consumerGroupManager) CreateWithEndOffsets(ctx context.Context, topic string, consumerGroup string) error {
	op := func() error {
		topicPartitions, err := c.adminClient.NumTopicPartitions([]string{topic})
		if err != nil {
			return fmt.Errorf("error getting number of partitions from kafka. topic %s, %w", topic, err)
		}

		offsets, err := LatestOffsets(c.adminClient.client, topic)
		if err != nil {
			return err
		}

		om, err := sarama.NewOffsetManagerFromClient(consumerGroup, c.adminClient.client)
		if err != nil {
			return fmt.Errorf("error creating kafka offset manager. topic: %s, consumer group: %s, %w", topic, consumerGroup, err)
		}
		defer om.Close()

		for partition := range len(topicPartitions) {
			pm, err := om.ManagePartition(topic, int32(partition))
			if err != nil {
				return err
			}

			// NOTE: MarkOffset can only commit an offset > the current offset. Verify this and panic if not true.
			next, _ := pm.NextOffset() // This is a new consumer group, so it should return -1 or -2
			if next >= 0 {
				panic(fmt.Sprintf("new consumer group %s should not have offsets on topic %s, but got next offset of %d on partition %d", consumerGroup, topic, next, partition))
			}

			partitionOffset := offsets[int32(partition)]
			if partitionOffset < 0 {
				panic(fmt.Sprintf("latest offset on topic %s partition %d must be >= 0, got %d", topic, partition, partitionOffset))
			}

			pm.MarkOffset(partitionOffset, "")
			if err := pm.Close(); err != nil {
				logging.Error(ctx, "error closing PartitionOffsetManager", kvp.Err(err))
				return err
			}
		}
		om.Commit()
		logging.Info(ctx, "created consumer group with offsets", kvp.String("topic", topic), kvp.String("consumer_group", consumerGroup), kvp.String("offsets", fmt.Sprintf("%+v", offsets)))
		return nil
	}

	return backoff.Retry(op, retry.DefaultBackOff(ctx, 10))
}

type AdminClient struct {
	makeAdminClient func() sarama.ClusterAdmin
	mutex           sync.Mutex
	adminClient     sarama.ClusterAdmin // NB: Don't use this. always call getAdminClient() instead.
	client          sarama.Client
}

func NewAdminClient(makeAdminClient func() sarama.ClusterAdmin, client sarama.Client) *AdminClient {
	return &AdminClient{makeAdminClient: makeAdminClient, client: client}
}

func (c *AdminClient) Close() error {
	err := errors.Join(c.client.Close(), c.closeAdminClient())
	if err != nil {
		return err
	}
	return nil
}

func (c *AdminClient) closeAdminClient() error {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	if c.adminClient != nil {
		err := c.adminClient.Close()
		c.adminClient = nil
		return err
	}
	return nil
}

func (c *AdminClient) getAdminClient() sarama.ClusterAdmin {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	if c.adminClient == nil {
		c.adminClient = c.makeAdminClient()
	}
	return c.adminClient
}

func (c *AdminClient) ListConsumerGroupOffsets(consumerGroup string, topics map[string][]int32) (*sarama.OffsetFetchResponse, error) {
	adminClient := c.getAdminClient()
	res, err := adminClient.ListConsumerGroupOffsets(consumerGroup, topics)
	if err != nil {
		cerr := c.closeAdminClient()
		return nil, errors.Join(err, cerr)
	}
	return res, nil
}

// GetLag returns lag for all partitions in the topic for a consumer group.
func (c *AdminClient) GetLag(ctx context.Context, consumerGroup string, topic string) (map[PartitionKey]int64, error) {
	lag := map[PartitionKey]int64{}

	op := func() error {
		var err error
		lag, err = c.getLag(ctx, consumerGroup, topic)
		return err
	}

	err := backoff.Retry(op, backoff.WithContext(backoff.WithMaxRetries(backoff.NewConstantBackOff(200*time.Millisecond), 1), ctx))
	if err != nil {
		return lag, fmt.Errorf("error getting lag: %w", err)
	}
	return lag, nil
}

// Fetch newest offsets on all incremental topic partitions.
func LatestOffsets(client sarama.Client, topic string) (map[int32]int64, error) {
	partitions, err := client.Partitions(topic)
	if err != nil {
		return nil, fmt.Errorf("error getting partitions: %w", err)
	}

	watermarks := map[int32]int64{}
	for _, partition := range partitions {
		offset, err := client.GetOffset(topic, partition, sarama.OffsetNewest)
		if err != nil {
			return nil, err
		}
		watermarks[partition] = offset
	}
	return watermarks, nil
}

func (c *AdminClient) IsConsumerGroupPresent(cg string) (bool, error) {
	adminClient := c.getAdminClient()
	cgList, err := adminClient.ListConsumerGroups()
	if err != nil {
		cerr := c.closeAdminClient()
		return false, errors.Join(err, cerr)
	}

	_, found := cgList[cg]
	return found, nil
}

// IsConsumerGroupPresentWithOffsets returns true if the consumer group has
// recorded offsets for every partition in the incremental and onboarding
// topics. Use this method when it is necessary to check that a consumer group
// is fully initialized before starting to use it.
//
// This matters because a consumer group "exists" as soon as an offset is
// recorded for any topic/partition. If a consumer starts using it before ALL
// the offsets are recorded, the Kafka client locks because offsets cannot be
// saved for an active consumer group.
func (c *AdminClient) IsConsumerGroupPresentWithOffsets(ctx context.Context, cg string, tc routing.TopicConfig) (bool, error) {
	topicPartitions := map[string][]int32{
		routing.OnboardSourceTopic:     {},
		routing.IncrementalSourceTopic: {},
	}
	for i := range tc.Onboard.Partitions {
		topicPartitions[routing.OnboardSourceTopic] = append(topicPartitions[routing.OnboardSourceTopic], i)
	}
	for i := range tc.Incremental.Partitions {
		topicPartitions[routing.IncrementalSourceTopic] = append(topicPartitions[routing.IncrementalSourceTopic], i)
	}

	adminClient := c.getAdminClient()
	offsets, err := adminClient.ListConsumerGroupOffsets(cg, topicPartitions)
	if err != nil {
		cerr := c.closeAdminClient()
		return false, errors.Join(err, cerr)
	}

	for i := range tc.Onboard.Partitions {
		block := offsets.GetBlock(routing.OnboardSourceTopic, i)
		if block == nil || block.Offset < 0 {
			return false, nil
		}
		logging.Info(ctx, "consumer group present", kvp.String("topic", routing.OnboardSourceTopic), kvp.Int("partition", int(i)), kvp.Int64("offset", block.Offset))
	}

	for i := range tc.Incremental.Partitions {
		block := offsets.GetBlock(routing.IncrementalSourceTopic, i)
		if block == nil || block.Offset < 0 {
			return false, nil
		}
		logging.Info(ctx, "consumer group present", kvp.String("topic", routing.IncrementalSourceTopic), kvp.Int("partition", int(i)), kvp.Int64("offset", block.Offset))
	}

	return true, nil
}

func (c *AdminClient) NumTopicPartitions(topics []string) (map[string]int, error) {
	topicPartitions := map[string]int{}
	if len(topics) == 0 {
		return topicPartitions, nil
	}

	adminClient := c.getAdminClient()

	topicMetadata, err := adminClient.DescribeTopics(topics)
	if err != nil {
		cerr := c.closeAdminClient()
		return nil, errors.Join(err, cerr)
	}

	for _, m := range topicMetadata {
		topicPartitions[m.Name] = len(m.Partitions)
	}

	return topicPartitions, nil
}

func (c *AdminClient) getLag(ctx context.Context, cg string, topic string) (map[PartitionKey]int64, error) {
	lag := map[PartitionKey]int64{}
	partitions, err := c.client.Partitions(topic)
	if err != nil {
		return nil, fmt.Errorf("error getting partitions: %w", err)
	}

	// Fetch the offsets for the consumer group used by the ingest pods.
	cgPresent, err := c.IsConsumerGroupPresent(cg)
	if err != nil {
		// Refresh the controller so that subsequent retries in the top-level GetLag have a chance to succeed.
		_, refreshErr := c.client.RefreshController()
		if refreshErr != nil {
			logging.Error(ctx, "failed to refresh Kafka client in getLag", kvp.Err(refreshErr))
		}

		return nil, fmt.Errorf("error checking consumer group availability: %w", err)
	}
	if !cgPresent {
		return nil, fmt.Errorf("consumer group %s is not available yet", cg)
	}

	res, err := c.ListConsumerGroupOffsets(cg, map[string][]int32{topic: partitions})
	if err != nil {
		cerr := c.closeAdminClient()
		return nil, fmt.Errorf("error listing consumer group offsets: %w; %w", err, cerr)
	}

	// Fetch newest offsets on all incremental topic partitions.
	watermarks, err := LatestOffsets(c.client, topic)
	if err != nil {
		return nil, err
	}

	for partition, offsetWaterMark := range watermarks {
		block := res.GetBlock(topic, partition)
		if block == nil {
			controllerKVP := kvp.String("kafka_controller_addr", "unknown")
			logging.Error(
				ctx,
				"response from Kafka did not contain offsets for all partitions: refreshing controller",
				kvp.String("response", fmt.Sprintf("%+v", res)),
				kvp.String("topic", topic),
				kvp.Int("missing_partition", int(partition)),
				kvp.String("consumer_group", cg),
				controllerKVP,
			)

			// Refresh the controller metadata so that the next call might succeed.
			_, err = c.client.RefreshController()
			if err != nil {
				logging.Error(ctx, "also failed to refresh the controller")
			}

			return nil, errors.New("failed to get offsets for all partitions")
		}
		lag[PartitionKey{topic, partition}] = offsetWaterMark - block.Offset
	}

	return lag, nil
}
