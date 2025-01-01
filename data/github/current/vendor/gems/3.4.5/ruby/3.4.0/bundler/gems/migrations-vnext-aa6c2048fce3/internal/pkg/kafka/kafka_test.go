package kafka

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/integration"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Kafka(t *testing.T) {
	addr := integration.SetupKafkaLiteTest(t)
	topic := integration.RandomString(10)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	producer, err := NewKafkaGoProducer(addr, topic, "", log.NewNullLogger())
	require.NoError(t, err)
	err = producer.Produce(ctx, []byte("test"))
	require.NoError(t, err)

	consumer := NewKafkaGoConsumer(addr, topic, "test-group", "", 10, log.NewNullLogger())

	var readMsgs []string
	var readMutex sync.Mutex
	go func() {
		err = consumer.Consume(ctx, func(_ context.Context, msg []byte) error {
			readMutex.Lock()
			readMsgs = append(readMsgs, string(msg))
			readMutex.Unlock()
			return nil
		})
	}()

	assert.Eventually(t, func() bool {
		readMutex.Lock()
		defer readMutex.Unlock()
		return len(readMsgs) == 1 && readMsgs[0] == "test"
	}, time.Minute, time.Second)
}
