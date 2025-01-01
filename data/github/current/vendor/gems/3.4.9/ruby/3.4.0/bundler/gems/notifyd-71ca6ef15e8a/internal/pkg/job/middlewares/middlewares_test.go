package middlewares

import (
	"context"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	aqclient "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	stats_mock "github.com/github/go-stats/mocks"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress/zlib"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/middlewares/mocks"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_PanicHandler(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name     string
		handler  job.HandlerFunc
		expected string
	}{
		{
			name:     "with a string panic",
			expected: "unhandled panic: oops (string)",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				panic("oops")
			},
		},
		{
			name:     "with an error panic",
			expected: "unhandled panic: oops (*errors.Error)",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				panic(errors.New("oops"))
			},
		},
		{
			name:     "with panic on an unknown format",
			expected: "unhandled panic: {} (struct {})",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				panic(struct{}{})
			},
		},
		{
			name:     "without a panic",
			expected: "",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				return nil
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			reporter := new(exceptions.ReporterMock)
			reporter.On("Report", mock.Anything, mock.Anything, mock.Anything).Return(nil)
			handler := newPanicHandler(reporter).Handle(test.handler)

			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(ghhydro.Message{}, clock.NewMock()))

			if test.expected != "" {
				r.Equal(test.expected, err.Error())
				r.True(errors.IsPanic(err))
				reporter.AssertNumberOfCalls(t, "Report", 1)
			} else {
				r.NoError(err)
				reporter.AssertNumberOfCalls(t, "Report", 0)
			}
		})
	}
}

func Test_StatsHandler(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name    string
		handler job.HandlerFunc
		check   func(*stats_mock.Client, error)
	}{
		{
			name: "with a handler that returns an error",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				return errors.New("oops")
			},
			check: func(statter *stats_mock.Client, err error) {
				statter.AssertCalled(t, "DistributionMs", defaultStatsKey, stats.Tags{"status": "failed", "error_type": "oops"}, mock.AnythingOfType("time.Duration"))
				statter.AssertCalled(t, "DistributionMs", genericStatsKey, stats.Tags{"status": "failed", "error_type": "oops"}, mock.AnythingOfType("time.Duration"))
				r.Error(err, "the error is propagated")
			},
		},
		{
			name: "with a handler that succeeds",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				return nil
			},
			check: func(statter *stats_mock.Client, err error) {
				statter.AssertCalled(t, "DistributionMs", defaultStatsKey, stats.Tags{"status": "succeeded"}, mock.AnythingOfType("time.Duration"))
				statter.AssertCalled(t, "DistributionMs", genericStatsKey, stats.Tags{"status": "succeeded"}, mock.AnythingOfType("time.Duration"))
				r.NoError(err)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			statter := new(stats_mock.Client)
			statter.On("DistributionMs", mock.Anything, mock.Anything, mock.Anything).Return()
			statter.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(statter)
			handler := newStatsHandler(statter, defaultStatsKey).Handle(test.handler)
			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(ghhydro.Message{}, clock.NewMock()))

			test.check(statter, err)
		})
	}
}

func Test_LoggerHandler(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name    string
		handler job.HandlerFunc
		setup   func(*mocks.LoggerMock)
		check   func(error)
	}{
		{
			name: "with a handler that returns an error",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				return errors.New("oops")
			},
			setup: func(logger *mocks.LoggerMock) {
				logger.On("Info", "processing message")
				logger.On("WithError", mock.Anything).Return(logger)
				logger.On("WithFields", mock.Anything).Return(logger)
				logger.On("Error", "message processed with error", mock.Anything)
			},
			check: func(err error) {
				r.Error(err, "the error is propagated")
			},
		},
		{
			name: "with a handler that returns no error",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				return nil
			},
			setup: func(logger *mocks.LoggerMock) {
				logger.On("WithFields", mock.Anything).Return(logger)
				logger.On("Info", "processing message").Once()
				logger.On("Info", "message processed", mock.Anything).Once()
			},
			check: func(err error) {
				r.NoError(err)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			handler := newLoggerHandler().Handle(test.handler)
			logger := mocks.NewLoggerMock(t)
			logger.On("WithContext", mock.Anything).Return(logger)
			test.setup(logger)
			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), logger, hydro.NewRequest(ghhydro.Message{}, clock.NewMock()))
			test.check(err)
		})
	}
}

func Test_ContextHandler(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name    string
		handler job.HandlerFunc
		check   func(error)
	}{
		{
			name: "with a handler that returns an error",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				requestID := o11y.CtxGetRequestID(ctx)
				r.NotEmpty(requestID, "the inner handler can see the request id")
				r.NotEqual("none", requestID, "the inner handler can see the request id")

				return errors.New("oops")
			},
			check: func(err error) {
				r.Error(err, "the error is propagated")
			},
		},
		{
			name: "with a handler that succeeds",
			handler: func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
				requestID := o11y.CtxGetRequestID(ctx)
				r.NotEmpty(requestID, "the inner handler can see the request id")
				r.NotEqual("none", requestID, "the inner handler can see the request id")

				return nil
			},
			check: func(err error) {
				r.NoError(err, "the nil error is propagated")
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			handler := newCtxHandler("test").Handle(test.handler)
			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(ghhydro.Message{}, clock.NewMock()))

			test.check(err)
		})
	}
}

func Test_DiscardableHandler(t *testing.T) {
	r := require.New(t)
	handler := func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		return errors.New("")
	}

	headersWithTopic := map[string]string{"topic": "some-topic"}
	headersWithPublishedTo := map[string]string{"notifyd-message-published-to": "aqueduct"}

	tests := []struct {
		name    string
		message job.Request
		error   bool
	}{
		{
			name:    "a message with an empty topic and headers is discarded",
			message: aqueduct.NewRequest(clock.NewMock(), logs.NullTelem, aqclient.ReceiveResult{}),
			error:   false,
		},
		{
			name:    "a message from hydro with a non-empty topic is processed that returns an error",
			message: hydro.NewRequest(ghhydro.Message{Topic: "some-topic"}, clock.NewMock()),
			error:   true,
		},
		{
			name:    "a message from aqueduct with a non-empty topic is processed that returns an error",
			message: aqueduct.NewRequest(clock.NewMock(), logs.NullTelem, aqclient.ReceiveResult{Job: aqclient.Job{Headers: headersWithTopic}}),
			error:   true,
		},
		{
			name:    "a message with an empty topic and published-to header is processed that returns an error",
			message: aqueduct.NewRequest(clock.NewMock(), logs.NullTelem, aqclient.ReceiveResult{Job: aqclient.Job{Headers: headersWithPublishedTo}}),
			error:   true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			handler := newDiscardableHandler().Handle(job.HandlerFunc(handler))
			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), test.message)
			if test.error {
				r.Error(err)
			} else {
				r.NoError(err)
			}
		})
	}
}

func Test_DecompressHandler(t *testing.T) {
	r := require.New(t)

	result := make([]byte, 255)
	handler := func(_ context.Context, _ tenancy.Tenant, _ log.Logger, req job.Request) error {
		result = req.Payload()
		return nil
	}

	message := []byte("hello, world\n")
	deflated, err := zlib.Deflate(message)
	r.NoError(err)

	headersWithDeflated := map[string]string{"content-encoding": "deflate"}

	tests := []struct {
		name    string
		request job.Request
	}{
		{
			name: "a message with plain payload",
			request: aqueduct.NewRequest(
				clock.NewMock(),
				logs.NullTelem,
				aqclient.ReceiveResult{Job: aqclient.Job{Payload: message}},
			),
		},
		{
			name: "a message with deflated payload",
			request: aqueduct.NewRequest(
				clock.NewMock(),
				logs.NullTelem,
				aqclient.ReceiveResult{Job: aqclient.Job{Headers: headersWithDeflated, Payload: deflated}},
			),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result = make([]byte, 255)

			handler := newDecompressHandler(clock.NewMock()).Handle(job.HandlerFunc(handler))
			err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), test.request)
			r.NoError(err)

			r.Equal(message, result)
		})
	}
}

func Test_ConcurrentHandler(t *testing.T) {
	oneDidRun := false
	one := job.HandlerFunc(func(_ context.Context, _ tenancy.Tenant, _ log.Logger, _ job.Request) error {
		oneDidRun = true
		return nil
	})

	two := job.HandlerFunc(func(_ context.Context, _ tenancy.Tenant, _ log.Logger, _ job.Request) error {
		return errors.New("discarded")
	})

	mainDidRun := false
	main := job.HandlerFunc(func(_ context.Context, _ tenancy.Tenant, _ log.Logger, _ job.Request) error {
		mainDidRun = true
		return nil
	})

	req := aqueduct.NewRequest(
		clock.NewMock(),
		logs.NullTelem,
		aqclient.ReceiveResult{},
	)

	err := NewConcurrentHandler(one, two).Handle(main).Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.NoError(t, err)

	require.True(t, oneDidRun)
	require.True(t, mainDidRun)
}

func Test_ConcurrentHandler_WithTimeout(t *testing.T) {
	oneDidRun := false
	one := job.HandlerFunc(func(ctx context.Context, _ tenancy.Tenant, _ log.Logger, _ job.Request) error {
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(50 * time.Millisecond):
			oneDidRun = true
			return nil
		}
	})

	mainDidRun := false
	main := job.HandlerFunc(func(_ context.Context, _ tenancy.Tenant, _ log.Logger, _ job.Request) error {
		mainDidRun = true
		return nil
	})

	req := aqueduct.NewRequest(
		clock.NewMock(),
		logs.NullTelem,
		aqclient.ReceiveResult{},
	)

	handler := NewConcurrentHandler(one).WithTimeout(5 * time.Millisecond)
	err := handler.Handle(main).Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.NoError(t, err)

	require.False(t, oneDidRun)
	require.True(t, mainDidRun)
}

func Test_TenantHandler(t *testing.T) {
	handler := newTenantHandler()
	t.Run("single tenant", func(tt *testing.T) {
		main := job.HandlerFunc(func(_ context.Context, tenant tenancy.Tenant, _ log.Logger, _ job.Request) error {
			require.IsType(tt, tenancy.SingleTenant{}, tenant, "The tenant is not of type SingleTenant")
			return nil
		})

		req := aqueduct.NewRequest(
			clock.NewMock(),
			logs.NullTelem,
			aqclient.ReceiveResult{},
		)

		err := handler.Handle(main).Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), req)
		require.NoError(tt, err)
	})

	t.Run("multi tenant", func(tt *testing.T) {
		main := job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, _ log.Logger, _ job.Request) error {
			switch ten := tenant.(type) {
			case tenancy.MultiTenant:
				require.Equal(tt, "avocado-gmbh", ten.Slug())
				require.Equal(tt, int64(123), ten.ID())

				require.Equal(tt, "avocado-gmbh", o11y.CtxGetTenantSlug(ctx), "The tenant's slug is not in the context")
			default:
				require.Fail(tt, "The tenant is not of type MultiTenant")
			}

			return nil
		})

		headers := map[string]string{
			"X-GitHub-Tenant":    "avocado-gmbh",
			"X-GitHub-Tenant-ID": "123",
		}
		req := aqueduct.NewRequest(
			clock.NewMock(),
			logs.NullTelem,
			aqclient.ReceiveResult{Job: aqclient.Job{Headers: headers}},
		)

		err := handler.Handle(main).Run(context.Background(), tenancy.NewMultiTenant(), log.NewNullLogger(), req)
		require.NoError(tt, err)
	})
}
