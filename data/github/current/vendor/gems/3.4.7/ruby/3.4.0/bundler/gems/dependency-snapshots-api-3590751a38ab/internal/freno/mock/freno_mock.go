package mock

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/stretchr/testify/mock"
)

type MockThrottler struct {
	mock.Mock
}

// CanWrite returns whether the delay is small enough for us to write
func (m *MockThrottler) CanWrite(ctx context.Context) (bool, error) {
	args := m.Called(ctx)
	return args.Get(0).(bool), args.Error(1)
}

func NewMockFrenoClient() *freno.FrenoClient {
	throttler := &MockThrottler{}
	throttler.On("CanWrite", mock.Anything).Return(true, nil)
	return &freno.FrenoClient{Client: throttler}
}
