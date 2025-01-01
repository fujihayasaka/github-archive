//go:build kafka
// +build kafka

package hydro_test

import (
	"context"
	"sync"
	"testing"

	"github.com/github/turboscan/ts/config"

	"github.com/github/go-stats"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/turboscan/ts/dbtest"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/hydro/topics"
)

type mockAnalysisEventProcessor struct {
	wg  sync.WaitGroup
	err error
	lm  *tshydro.Analysis
}

func (a *mockAnalysisEventProcessor) ProcessorName() string {
	return "AnalysisEventProcessor"
}

func (a *mockAnalysisEventProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	a.err = err
	return nil
}

func (a *mockAnalysisEventProcessor) ProcessEnvelope(_ context.Context, e *envelope.Envelope, topic string) error {
	var msg tshydro.Analysis
	if err := proto.Unmarshal(e.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling analysis message")
	}

	a.lm = &msg
	a.wg.Done()
	return nil
}

func (a *mockAnalysisEventProcessor) Topics() []string {
	return []string{topics.NewAnalysis}
}

func (a *mockAnalysisEventProcessor) GetRetryPolicy() consumers.RetryPolicy {
	return consumers.RetryPolicy{}
}

func (a *mockAnalysisEventProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}
func (a *mockAnalysisEventProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

func TestBothProduceAndConsume(t *testing.T) {
	ctx := context.Background()
	cfg, err := config.Load()
	require.NoError(t, err)

	kc, err := hydro.NewKafkaConfig([]string{cfg.KafkaBrokers}, hydro.WithKafkaVersion(cfg.KafkaVersion))
	require.NoError(t, err)

	processor := &mockAnalysisEventProcessor{}
	consumer, err := consumers.NewConsumerServer(*kc, "test-group", processor, dbtest.Logger)

	require.NoError(t, err)
	defer consumer.Stop(ctx)
	go consumer.Start(ctx)

	publisher, err := publishers.New(*kc, stats.NullStatter)
	require.NoError(t, err)

	msg := &tshydro.Analysis{
		RepositoryId: uint64(42),
		SarifUri:     "foo.sarif",
		CommitOid:    "beef",
		Ref:          []byte("arthurnn/test"),
	}

	processor.wg.Add(1)
	err = publisher.NewAnalysis(ctx, msg)
	require.NoError(t, err)
	processor.wg.Wait()

	require.Equal(t, uint64(42), processor.lm.RepositoryId)
	require.Equal(t, []byte("arthurnn/test"), processor.lm.Ref)
}
