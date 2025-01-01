// Package mocks contains mocks shared by tests.
package mocks

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/flipper"
	"github.com/stretchr/testify/mock"
)

type Flipper struct {
	mock.Mock
}

var _ flipper.Flipper = &Flipper{}

func (m *Flipper) IsEnabled(ctx context.Context, feature, actorID string) (bool, error) {
	args := m.Called(ctx, feature, actorID)
	return args.Bool(0), args.Error(1)
}

func (m *Flipper) IsGloballyEnabled(ctx context.Context, feature string) (bool, error) {
	args := m.Called(ctx, feature)
	return args.Bool(0), args.Error(1)
}

var IsContext = mock.MatchedBy(Is[context.Context])

func Is[T any](T) bool {
	return true
}

func Cleanup[M interface{ AssertExpectations(mock.TestingT) bool }](tb testing.TB, m M) M {
	tb.Helper()
	tb.Cleanup(func() {
		m.AssertExpectations(tb)
	})
	return m
}
