package retries

import (
	context "context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/log"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/hydro"
	hydrotesthelper "github.com/github/notifyd/internal/pkg/hydro/testhelper"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_Middleware_Handle(t *testing.T) {
	r := require.New(t)
	msg := hydrotesthelper.BuildHydroMsg(t, new(pb.Notify))

	t.Run("when the handler fails with a retriable error", func(t *testing.T) {
		e := errors.New("oops").With(errors.MarkRetriable())
		retrier := newRetrierMock(t)
		retrier.On("Retry", mock.Anything, mock.Anything, mock.Anything).Return(nil)
		m := &Middleware{retrier: retrier}
		handler := m.Handle(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
			return e
		}))
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(msg, clock.NewMock()))

		r.ErrorIs(err, e)
	})

	t.Run("when the handler fails with a non retriable error", func(t *testing.T) {
		e := errors.New("oops")
		retrier := new(retrierMock)
		retrier.On("Retry", mock.Anything, mock.Anything, mock.Anything).Return(nil)
		m := &Middleware{retrier: retrier}
		handler := m.Handle(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
			return e
		}))
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(msg, clock.NewMock()))

		r.ErrorIs(err, e)
		retrier.AssertNotCalled(t, "Retry")
	})

	t.Run("when the handler success", func(t *testing.T) {
		m := &Middleware{}
		handler := m.Handle(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
			return nil
		}))
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(msg, clock.NewMock()))
		r.NoError(err, "the request passes by")
	})

	t.Run("when the retrier fails", func(t *testing.T) {
		e := errors.New("oops").With(errors.MarkRetriable())
		retrierErr := errors.New("retrier errored")
		retrier := newRetrierMock(t)
		retrier.On("Retry", mock.Anything, mock.Anything, mock.Anything).Return(retrierErr)
		reporter := exceptions.NewReporterMock(t)
		m := &Middleware{retrier: retrier, reporter: reporter}
		handler := m.Handle(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
			return e
		}))
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(msg, clock.NewMock()))

		r.ErrorIs(err, e, "the error is propagated")
	})

	t.Run("when the retrier panics", func(t *testing.T) {
		retrier := newRetrierMock(t)
		retrier.On("Retry", mock.Anything, mock.Anything, mock.Anything).Panic("boom")
		reporter := exceptions.NewReporterMock(t)
		reporter.On("Report", mock.Anything, mock.Anything, mock.Anything).Return(nil)
		m := &Middleware{retrier: retrier, reporter: reporter}
		handler := m.Handle(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
			return errors.New("oops").With(errors.MarkRetriable())
		}))
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), hydro.NewRequest(ghhydro.Message{}, clock.NewMock()))

		r.Contains(err.Error(), "oops")
	})
}
