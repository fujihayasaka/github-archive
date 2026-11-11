package kafka

import (
	"context"
	"fmt"

	"github.com/IBM/sarama"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	hydroschemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	blackbird_pb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	"github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// A wrapper type for AssignmentSnapshot message that also contains the
// kafka offset of that particular message.
type AssignmentSnapshot struct {
	Msg         *blackbird_pb.AssignmentSnapshot
	KafkaOffset int64
}

//go:generate counterfeiter . AssignmentsReader
type AssignmentsReader interface {
	// ReadAtOffset reads AssignmentSnapshot message from ShardAssignmentSnapshot at the provided offset.
	ReadAtOffset(ctx context.Context, cluster string, epochID types.EpochID, offset int64) (*AssignmentSnapshot, error)
}

// A ShardAssignmentSnapshotConsumer allows the clients to read messages from ShardAssignmentSnapshot kafka topic
// it utilizes sarama's GetOffset api to seek a kafka topic based on unix timestamp.
type assignmentsReader struct {
	clientProvider func() (sarama.Client, error)
}

func NewAssignmentsReader(clientProvider func() (sarama.Client, error)) *assignmentsReader {
	return &assignmentsReader{clientProvider}
}

func (r *assignmentsReader) ReadAtOffset(ctx context.Context, cluster string, epochID types.EpochID, offset int64) (*AssignmentSnapshot, error) {
	client, err := r.clientProvider()
	if err != nil {
		return nil, err
	}

	defer client.Close()

	topic, err := routing.ShardAssignmentSnapshotTopicForCluster(cluster)
	if err != nil {
		return nil, err
	}

	ctx = logging.With(ctx, kvp.String("cluster", cluster), kvp.Int("epoch", int(epochID)), kvp.String("topic", topic), kvp.Int("offset", int(offset)))

	if offset == sarama.OffsetNewest {
		offset, err = client.GetOffset(topic, 0, sarama.OffsetNewest)
		if err != nil {
			return nil, errors.Wrapf(err, "error when calling client.GetOffset with offset %d", offset)
		}
		// There are no messages on the topic,`GetOffset` told us that the next message for
		// snapshot topic be the first one e.g. with offset 0.
		if offset == 0 {
			return nil, fmt.Errorf("no messages on the %s topic", topic)
		}
		// Adjust the offset since the asking for offset with `sarama.OffsetNewest` will return
		// the next offset that will be produced.
		offset = offset - 1
	}

	assignments, err := readMessages(ctx, client, cluster, epochID, topic, offset, offset)
	if err != nil {
		return nil, err
	}
	if len(assignments) == 0 {
		return nil, fmt.Errorf("no assignments found at offset %d", offset)
	}

	return assignments[0], nil
}

func readMessages(
	ctx context.Context,
	client sarama.Client,
	cluster string,
	epochID types.EpochID,
	topic string,
	startOffset,
	endOffset int64,
) ([]*AssignmentSnapshot, error) {
	consumer, err := sarama.NewConsumerFromClient(client)
	if err != nil {
		return nil, err
	}
	defer consumer.Close()

	snapshots := []*AssignmentSnapshot{}
	partitionConsumer, err := consumer.ConsumePartition(topic, 0, (startOffset))
	if err != nil {
		return nil, err
	}

	logging.Info(ctx, "starting ShardAssignmentSnapshot consumer", kvp.Int64("start_offset", startOffset), kvp.Int64("end_offset", endOffset))
	defer partitionConsumer.Close()

	for {
		select {
		case msg := <-partitionConsumer.Messages():
			envolope := hydroschemas.Envelope{}
			if err := proto.Unmarshal(msg.Value, &envolope); err != nil {
				return nil, err
			}

			snapshot := &blackbird_pb.AssignmentSnapshot{}
			if err := proto.Unmarshal(envolope.Message, snapshot); err != nil {
				return nil, err
			}
			if snapshot.GetVersion().GetEpochId() == uint32(epochID) {
				snapshots = append(snapshots, &AssignmentSnapshot{
					Msg:         snapshot,
					KafkaOffset: msg.Offset,
				})
			}
			if msg.Offset == endOffset {
				logging.Info(ctx, "requested end offset has been reached for ShardAssignmentSnapshot", kvp.Int("num_assignment_snapshot", len(snapshots)))
				return snapshots, nil
			}
		case <-ctx.Done():
			logging.Info(ctx, "context canceled, returning what's accumulated so far")
			return snapshots, nil
		}
	}
}
