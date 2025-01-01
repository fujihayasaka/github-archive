package job

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/stretchr/testify/require"
)

var _ Builder = &testMiddleware{}

type testMiddleware struct {
	called *[]string
	name   string
}

func (h *testMiddleware) Handle(next Handler) HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req Request) error {
		*h.called = append(*h.called, h.name)
		return next.Run(ctx, tenant, logger, req)
	}
}

func Test_Chain(t *testing.T) {
	r := require.New(t)

	t.Run("with middlewares", func(t *testing.T) {
		called := []string{}
		outer := &testMiddleware{called: &called, name: "outer"}
		middle := &testMiddleware{called: &called, name: "middle"}
		inner := &testMiddleware{called: &called, name: "inner"}
		err := errors.New("oops")

		chain := NewChain(outer, middle, inner)
		handler := chain.Then(HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req Request) error {
			called = append(called, "handler")
			return err
		}))

		hErr := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), nil)

		r.ErrorIs(hErr, err)
		r.Equal("outer", called[0])
		r.Equal("middle", called[1])
		r.Equal("inner", called[2])
		r.Equal("handler", called[3])
	})

	t.Run("with an empty chain", func(t *testing.T) {
		chain := NewChain()
		err := errors.New("oops")
		handler := chain.Then(HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req Request) error {
			return err
		}))
		hErr := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), nil)
		r.ErrorIs(hErr, err)
	})

	t.Run("without a handler", func(t *testing.T) {
		chain := NewChain()
		handler := chain.Then(nil)
		err := handler.Run(context.Background(), tenancy.NewSingleTenant(), log.NewNullLogger(), nil)
		r.ErrorIs(err, ErrNoHandlerProvided)
	})
}
