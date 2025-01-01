package kafka

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_offsetCommiter_seen(t *testing.T) {
	t.Run("initializing with first message", func(t *testing.T) {
		o := newOffsetCommiter("", log.NewNullLogger())
		m := &kafka.Message{
			Partition: 0,
			Offset:    0,
		}

		o.seen(m)

		assert.Equal(t, map[int]struct{}{0: {}}, o.initialized)
		assert.Equal(t, map[int]int64{0: -1}, o.committed)
		assert.Equal(t, map[int]int64{0: -1}, o.committed)
	})

	t.Run("initializing with second message", func(t *testing.T) {
		o := newOffsetCommiter("", log.NewNullLogger())
		m := &kafka.Message{
			Partition: 0,
			Offset:    1,
		}

		o.seen(m)

		assert.Equal(t, map[int]struct{}{0: {}}, o.initialized)
		assert.Equal(t, map[int]int64{0: 0}, o.committed)
	})
}

func Test_offsetCommiter_processed(t *testing.T) {
	// commitFn is a function that mocks the kafka.Reader.CommitMessages method
	var msgs []kafka.Message
	commitFn := func(ctx context.Context, m ...kafka.Message) error {
		msgs = append(msgs, m...)
		return nil
	}

	o := newOffsetCommiter("", log.NewNullLogger())

	// First message is committed
	m := &kafka.Message{
		Partition: 0,
		Offset:    0,
	}
	o.seen(m)

	err := o.processed(context.Background(), commitFn, m)
	require.NoError(t, err)

	assert.Equal(t, map[int]struct{}{0: {}}, o.initialized)
	assert.Equal(t, map[int]int64{0: 0}, o.committed)
	assert.Len(t, o.pending[0], 0)
	assert.Equal(t, []kafka.Message{*m}, msgs)

	// Third message creates a gap because the second message was not processed yet
	msgs = nil
	m.Offset = 2
	o.seen(m)
	err = o.processed(context.Background(), commitFn, m)
	require.NoError(t, err)
	assert.Equal(t, map[int]int64{0: 0}, o.committed)
	assert.Equal(t, map[int]map[int64]struct{}{0: {2: {}}}, o.pending)
	assert.Empty(t, msgs)

	// Second message triggers a commit of second and third message offsets
	msgs = nil
	m.Offset = 1
	o.seen(m)
	err = o.processed(context.Background(), commitFn, m)
	require.NoError(t, err)
	assert.Equal(t, map[int]int64{0: 2}, o.committed)
	assert.Len(t, o.pending[0], 0)
	assert.Equal(t, []kafka.Message{{Partition: 0, Offset: 2}}, msgs)
}
