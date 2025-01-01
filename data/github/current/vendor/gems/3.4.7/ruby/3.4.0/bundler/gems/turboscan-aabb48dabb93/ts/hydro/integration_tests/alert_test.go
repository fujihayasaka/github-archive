//go:build kafka
// +build kafka

package hydro_test

import (
	"context"
	"sync"
	"testing"

	"github.com/github/go-stats"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/hydro/topics"
)

type mockAlertEventProcessor struct {
	wg  sync.WaitGroup
	err error
	lm  *oldtshydro.AlertEvent
}

func (a *mockAlertEventProcessor) ProcessorName() string {
	return "AlertEventProcessor"
}

func (a *mockAlertEventProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	a.err = err
	return nil
}

func (a *mockAlertEventProcessor) ProcessEnvelope(_ context.Context, e *envelope.Envelope, topic string) error {
	var msg oldtshydro.AlertEvent
	if err := proto.Unmarshal(e.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling alert message")
	}

	a.lm = &msg
	a.wg.Done()
	return nil
}

func (a *mockAlertEventProcessor) Topics() []string {
	return []string{topics.AlertEvent}
}

func (a *mockAlertEventProcessor) GetRetryPolicy() consumers.RetryPolicy {
	return consumers.RetryPolicy{}
}

func (a *mockAlertEventProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}
func (a *mockAlertEventProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

func TestBothProduceAndConsume_Alert(t *testing.T) {
	ctx := context.Background()
	cfg, err := config.Load()
	require.NoError(t, err)

	kc, err := hydro.NewKafkaConfig([]string{cfg.KafkaBrokers}, hydro.WithKafkaVersion(cfg.KafkaVersion))
	require.NoError(t, err)

	handler := &mockAlertEventProcessor{}
	consumer, err := consumers.NewConsumerServer(*kc, "test-group", handler, dbtest.Logger)

	require.NoError(t, err)
	defer consumer.Stop(ctx)
	go consumer.Start(ctx)

	publisher, err := publishers.New(*kc, stats.NullStatter)
	require.NoError(t, err)

	msg := &oldtshydro.AlertEvent{
		RepositoryId: int32(42),
		Ref:          "arthurnn/test",
	}

	handler.wg.Add(1)
	err = publisher.AlertEvent(ctx, msg)
	require.NoError(t, err)
	handler.wg.Wait()

	require.Equal(t, int32(42), handler.lm.RepositoryId)
	require.Equal(t, "arthurnn/test", handler.lm.Ref)
}
