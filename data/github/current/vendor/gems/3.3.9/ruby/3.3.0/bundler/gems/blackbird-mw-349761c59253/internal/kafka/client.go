package kafka

import (
	"context"
	"fmt"
	"sync"
	"time"

	"errors"

	"github.com/IBM/sarama"
	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
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

	// CreateConsumerGroupWithLatestOffsets creates a new consumer group in kafka with the latest offsets for the given topic.
	// Similar to CreateConsumerGroup, the latest offsets are committed atomically.
	CreateWithLatestOffsets(ctx context.Context, topic string, consumerGroup string) error
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
			return fmt.Errorf("error creating kafka offset manager. topic: %s, consumer group: %s, %w", topic, consumerGroup, err)
		}
		defer om.Close()

		for partition, offset := range offsets {
			pm, err := om.ManagePartition(topic, partition)
			if err != nil {
				return err
			}
			pm.MarkOffset(offset, "")
		}
		om.Commit()

		return nil
	}

	return backoff.Retry(op, retry.DefaultBackOff(ctx, 10))

}

func (c *consumerGroupManager) CreateWithLatestOffsets(ctx context.Context, topic string, consumerGroup string) error {
	op := func() error {
		topicPartitions, err := c.adminClient.NumTopicPartitions([]string{topic})
		if err != nil {
			return fmt.Errorf("error getting number of partitions from kafka. topic %s, %w", topic, err)
		}

		om, err := sarama.NewOffsetManagerFromClient(consumerGroup, c.adminClient.client)
		if err != nil {
			return fmt.Errorf("error creating kafka offset manager. topic: %s, consumer group: %s, %w", topic, consumerGroup, err)
		}
		defer om.Close()

		for i := 0; i < len(topicPartitions); i++ {
			pm, err := om.ManagePartition(topic, int32(i))
			if err != nil {
				return err
			}

			pm.ResetOffset(sarama.OffsetNewest, "")
		}
		om.Commit()

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

func (c *AdminClient) GetMaxLag(ctx context.Context, corpus routing.Corpus, epochID types.EpochID, topic string, tags stats.Tags) (int64, error) {
	lag := int64(0)

	op := func() error {
		var err error
		lag, err = c.getMaxLag(ctx, corpus, epochID, topic, tags)
		return err
	}

	err := backoff.Retry(op, backoff.WithContext(backoff.WithMaxRetries(backoff.NewConstantBackOff(200*time.Millisecond), 1), ctx))
	if err != nil {
		return lag, fmt.Errorf("error getting max lag: %w", err)
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

func (c *AdminClient) getMaxLag(ctx context.Context, corpus routing.Corpus, epochID types.EpochID, topic string, tags stats.Tags) (int64, error) {
	maxLag := int64(0)
	partitions, err := c.client.Partitions(topic)
	if err != nil {
		return maxLag, fmt.Errorf("error getting partitions: %w", err)
	}

	// Fetch the offsets for the consumer group used by the ingest pods.
	cg := corpus.ConsumerGroup(epochID)
	cgPresent, err := c.IsConsumerGroupPresent(cg)
	if err != nil {
		return maxLag, fmt.Errorf("error checking consumer group availability: %w", err)
	}
	if !cgPresent {
		return maxLag, fmt.Errorf("consumer group %s is not available yet, lag won't be reported", cg)
	}

	res, err := c.ListConsumerGroupOffsets(cg, map[string][]int32{topic: partitions})
	if err != nil {
		cerr := c.closeAdminClient()
		return maxLag, fmt.Errorf("error listing consumer group offsets: %w; %w", err, cerr)
	}

	// Fetch newest offsets on all incremental topic partitions.
	watermarks, err := LatestOffsets(c.client, topic)
	if err != nil {
		return maxLag, err
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

			return 0, errors.New("failed to get offsets for all partitions")
		}
		lag := offsetWaterMark - block.Offset
		if lag > maxLag {
			maxLag = lag
		}
		statting.Gauge(ctx, "incremental_lag", lag,
			stats.Tags{
				"corpus":    corpus.String(),
				"topic":     topic,
				"cg":        cg,
				"partition": fmt.Sprintf("%d", partition),
			}.Merge(tags))
	}
	return maxLag, nil
}
