package consumers

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/proto"

	"github.com/github/turboscan/ts/mocks"
)

type mockAnalysisProcessor struct {
	wg  sync.WaitGroup
	err error

	handleError        func(context.Context, error, *hydro.Message) error
	newAnalysis        func(context.Context, *tshydro.Analysis) error
	beforeRetry        func(context.Context, error, int, *envelope.Envelope, *hydro.Message)
	onPermanentFailure func(context.Context, *envelope.Envelope, *hydro.Message) error
}

func (mock *mockAnalysisProcessor) ProcessorName() string {
	return "AnalysisProcessor"
}

func (mock *mockAnalysisProcessor) ProcessEnvelope(ctx context.Context, e *envelope.Envelope, topic string) error {
	var msg tshydro.Analysis
	if err := UnwrapAnalysisMessage(e.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling analysis message")
	}

	return mock.newAnalysis(ctx, &msg)
}
func (mock *mockAnalysisProcessor) HandleError(ctx context.Context, e error, m *hydro.Message) error {
	return mock.handleError(ctx, e, m)
}

func (mock *mockAnalysisProcessor) Topics() []string {
	return []string{"topic.Analysis"}
}

func (mock *mockAnalysisProcessor) Log(buf []byte, lvl log.Level, now time.Time, message string, ctx, fields []kvp.Field) {
	var err error
	for _, field := range fields {
		if field.Key == "error" {
			err = errors.New(field.String)
		}
	}
	_ = mock.handleError(nil, err, nil)
}

func (mock *mockAnalysisProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{}
}

func (mock *mockAnalysisProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
	mock.beforeRetry(ctx, lastErr, errCnt, e, m)
}
func (mock *mockAnalysisProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return mock.onPermanentFailure(ctx, e, m)
}

func TestConsumer_ErrorMessageDiffTopic(t *testing.T) {
	ctx := context.Background()
	ch := make(chan hydro.Message, 2)
	defer close(ch)

	c := &mockAnalysisProcessor{}

	src, err := hydro.NewMemorySource(ch)
	require.NoError(t, err)

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)

	// Additional logging method calls will be chained onto calls to
	// the WithError method stubbed below, so it needs to return
	// something that can handle them. To avoid confusion about
	// expectations, we make a new logger for this. To avoid data races
	// we create it here, in the main goroutine.
	// cf https://github.com/golang/mock/issues/533#issuecomment-821537840
	subsequentLogger := mocks.NewMockLogger(mockCtrl)
	subsequentLogger.EXPECT().Error(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).MinTimes(0)

	logger.
		EXPECT().
		WithError(gomock.Any()).
		DoAndReturn(func(err error) log.Logger {
			c.wg.Done()
			require.Equal(t, "received message for unexpected topic \"foo\"", err.Error())

			return subsequentLogger
		})

	svc := &ConsumerServer{
		source:    src,
		processor: nil,
		logger:    logger,
	}

	defer func() {
		require.NoError(t, svc.Stop(ctx))
	}()
	go func() {
		require.NoError(t, svc.Start(ctx))
	}()

	c.wg.Add(1)
	ch <- hydro.Message{
		Topic: "foo",
		Value: []byte{0x1},
	}
	c.wg.Wait()
}

func TestConsumer_ErrorMarshal(t *testing.T) {
	ctx := context.Background()
	ch := make(chan hydro.Message, 2)

	defer close(ch)

	c := &mockAnalysisProcessor{}
	c.handleError = func(_ context.Context, e error, _ *hydro.Message) error {
		c.err = e
		c.wg.Done()
		return nil
	}

	src, err := hydro.NewMemorySource(ch)
	require.NoError(t, err)
	svc := &ConsumerServer{
		source:    src,
		processor: c,
	}
	defer func() {
		require.NoError(t, svc.Stop(ctx))
	}()
	go func() {
		require.NoError(t, svc.Start(ctx))
	}()

	c.wg.Add(1)
	ch <- hydro.Message{
		Topic: c.Topics()[0],
		Value: []byte{0x1},
	}
	c.wg.Wait()

	require.Regexp(t, "unmarshalling hydro envelope: proto:(\u00a0| )cannot parse invalid wire-format data", c.err.Error())
}

func TestConsumer_ErrorRetry(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	ch := make(chan hydro.Message, 1)
	defer close(ch)

	c := &mockAnalysisProcessor{}
	counter := 2
	c.wg.Add(counter)
	c.handleError = func(_ context.Context, e error, m *hydro.Message) error {
		c.wg.Done()
		require.Equal(t, m.Value, []byte{0x42}, "only retry first message")
		counter--
		if counter <= 0 {
			cancel()
			return context.Canceled
		}

		return e
	}

	src, err := hydro.NewMemorySource(ch)
	require.NoError(t, err)
	svc := &ConsumerServer{
		source:    src,
		processor: c,
	}

	defer func() {
		require.NoError(t, svc.Stop(ctx))
	}()
	go func() {
		require.Equal(t, context.Canceled, svc.Start(ctx))
	}()

	ch <- hydro.Message{
		Topic: c.Topics()[0],
		Value: []byte{0x42},
	}
	ch <- hydro.Message{
		Topic: c.Topics()[0],
		Value: []byte{0x43},
	}

	c.wg.Wait()
}

func TestConsumer_NewMessagePanic(t *testing.T) {
	ctx := context.Background()
	ch := make(chan hydro.Message, 2)
	defer close(ch)

	c := &mockAnalysisProcessor{}
	c.newAnalysis = func(_ context.Context, a *tshydro.Analysis) error {
		panic("woot")
	}
	c.handleError = func(_ context.Context, e error, _ *hydro.Message) error {
		c.err = e
		c.wg.Done()
		return nil
	}

	c.beforeRetry = func(_ context.Context, err error, errCnt int, _ *envelope.Envelope, _ *hydro.Message) {
		require.Equal(t, "hydro consumer panic handling message: woot", err.Error())
	}

	c.onPermanentFailure = func(_ context.Context, _ *envelope.Envelope, _ *hydro.Message) error {
		return nil
	}

	src, err := hydro.NewMemorySource(ch)
	require.NoError(t, err)
	svc := &ConsumerServer{
		source:    src,
		processor: c,
	}

	// test cleanup
	defer func() {
		require.NoError(t, svc.Stop(ctx))
	}()
	go func() {
		require.NoError(t, svc.Start(ctx))
	}()

	c.wg.Add(1)
	ch <- hydro.Message{
		Topic: c.Topics()[0],
		Value: WrapEnvelope(t, WrapAnalysisMessage(t, &tshydro.Analysis{RepositoryId: 42})),
	}
	c.wg.Wait()

	// We log the panic but we catch it in the retry loop and continue
	require.Equal(t, "hydro consumer panic handling message: woot", c.err.Error())
}

func TestConsumer_NewMessage(t *testing.T) {
	ctx := context.Background()
	ch := make(chan hydro.Message, 2)
	defer close(ch)

	c := &mockAnalysisProcessor{}
	c.newAnalysis = func(ctx context.Context, a *tshydro.Analysis) error {
		require.Equal(t, uint64(42), a.RepositoryId)
		require.Equal(t, tenant.GetTenant(ctx), "avocado")
		require.Equal(t, tenant.GetTenantID(ctx), "12345")
		c.wg.Done()
		return nil
	}
	c.handleError = func(_ context.Context, _ error, _ *hydro.Message) error {
		t.FailNow()
		return nil
	}

	src, err := hydro.NewMemorySource(ch)
	require.NoError(t, err)
	svc := &ConsumerServer{
		source:    src,
		processor: c,
	}
	defer func() {
		require.NoError(t, svc.Stop(ctx))
	}()
	go func() {
		require.NoError(t, svc.Start(ctx))
	}()

	c.wg.Add(1)
	ch <- hydro.Message{
		Topic:   c.Topics()[0],
		Value:   WrapEnvelope(t, WrapAnalysisMessage(t, &tshydro.Analysis{RepositoryId: 42})),
		Headers: map[string]string{headers.Tenant: "avocado", headers.TenantID: "12345"},
	}
	c.wg.Wait()
}

func WrapEnvelope(t *testing.T, msg []byte) []byte {
	t.Helper()

	env := &envelope.Envelope{Message: msg}
	data, err := proto.Marshal(env)
	require.NoError(t, err)

	return data
}

func WrapAnalysisMessage(t *testing.T, a *tshydro.Analysis) []byte {
	t.Helper()

	data, err := proto.Marshal(a)
	require.NoError(t, err)
	return data
}
