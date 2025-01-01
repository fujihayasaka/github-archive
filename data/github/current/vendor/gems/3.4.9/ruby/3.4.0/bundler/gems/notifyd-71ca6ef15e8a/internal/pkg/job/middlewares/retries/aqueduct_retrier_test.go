package retries

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/go-config"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	hydro_th "github.com/github/notifyd/internal/pkg/hydro/testhelper"
	internaljob "github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_Retrier_Retry(t *testing.T) {
	r := require.New(t)
	senderMock := aqueduct.NewSenderMock(t)
	cfg := Config{BaseBackoff: 0, ExponentialFactor: 0, MaxAttempts: 1}
	senderMock.On("Send", mock.Anything, mock.MatchedBy(func(job ghaqueduct.Job) bool {
		return job.Headers[string(internaljob.HeaderPublishedTo)] == "aqueduct"
	})).Return("", nil)
	notifyMsg := new(pb.Notify)
	retrier := AqueductRetrier{
		cfg:     cfg,
		telem:   logs.NullTelem,
		statter: stats.NullStatter,
		client:  senderMock,
		clock:   clock.NewMock(),
	}

	msg := hydro_th.BuildHydroMsg(t, notifyMsg).Value
	err := retrier.Retry(context.Background(), tenancy.NewSingleTenant(), msg)
	r.NoError(err)
}

func Test_Retrier_Retry_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	r := require.New(t)
	clientConfig := aqueduct.ClientConfig{}
	err := config.Load(&clientConfig)
	r.NoError(err)
	retriesConfig := Config{}
	err = config.Load(&retriesConfig)
	r.NoError(err)

	notifyMsg := new(pb.Notify)
	client, err := aqueduct.NewClient(clientConfig, logs.NullTelem.Logger, stats.NullStatter)
	r.NoError(err)

	retrier := AqueductRetrier{
		cfg:     retriesConfig,
		telem:   logs.NullTelem,
		statter: stats.NullStatter,
		client:  client,
		clock:   clock.NewMock(),
	}

	msg := hydro_th.BuildHydroMsg(t, notifyMsg).Value
	err = retrier.Retry(context.Background(), tenancy.NewSingleTenant(), msg)
	r.NoError(err)
}

func Test_Retrier_shouldHalt(t *testing.T) {
	r := require.New(t)
	cfg := Config{MaxAttempts: 5}
	retrier := AqueductRetrier{cfg: cfg}

	t.Run("true when the attempts limit has been reached", func(t *testing.T) {
		r.True(retrier.shouldHalt(&dummyRetriable{attempts: 6}))
	})

	t.Run("false when the attempts limit has been reached", func(t *testing.T) {
		r.False(retrier.shouldHalt(&dummyRetriable{attempts: 5}))
		r.False(retrier.shouldHalt(&dummyRetriable{attempts: 4}))
	})
}

func Test_Retrier_deliverAt(t *testing.T) {
	r := require.New(t)
	cfg := Config{
		BaseBackoff:       5 * time.Second,
		JitterFactor:      0.1,
		ExponentialFactor: 2.0,
	}
	clk := clock.NewMock()
	now := clk.Now()
	retrier := AqueductRetrier{cfg: cfg, telem: logs.NullTelem, statter: stats.NullStatter, clock: clk}

	tests := []struct {
		attempt         int32
		expectedBackoff time.Duration
		delta           float64
	}{
		{
			attempt:         1,
			expectedBackoff: 2 * 5 * time.Second,
			delta:           0.2 * float64(5*time.Second),
		},
		{
			attempt:         5,
			expectedBackoff: 32 * 5 * time.Second,
			delta:           3.2 * float64(5*time.Second),
		},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("on attempt %d", test.attempt), func(t *testing.T) {
			deliverAt, err := retrier.deliverAt(context.Background(), &dummyRetriable{attempts: test.attempt})
			r.NoError(err)
			expectedDeliverAt := now.Add(test.expectedBackoff)
			r.InDelta(
				expectedDeliverAt.Nanosecond(),
				deliverAt.Nanosecond(),
				test.delta,
			)
		})
	}
}

type dummyRetriable struct{ attempts int32 }

var _ retriables.Message = &dummyRetriable{}

func (r *dummyRetriable) GetRetries() *entities_pb.Retries    { panic("unreachable") }
func (r *dummyRetriable) GetAttempts() int32                  { return r.attempts }
func (r *dummyRetriable) UpdateRetries()                      { panic("unreachable") }
func (r *dummyRetriable) Encode() ([]byte, error)             { panic("unreachable") }
func (r *dummyRetriable) From(*hydro_pb.Envelope) error       { panic("unreachable") }
func (r *dummyRetriable) GetName() string                     { panic("unreachable") }
func (r *dummyRetriable) GetTopicFormat() ghhydro.TopicFormat { panic("unreachable") }
func (r *dummyRetriable) HydroMessage() proto.Message         { panic("unreachable") }
func (r *dummyRetriable) Queue() string                       { panic("unreachable") }
