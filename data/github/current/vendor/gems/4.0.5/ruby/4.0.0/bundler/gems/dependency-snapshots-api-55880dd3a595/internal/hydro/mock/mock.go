package mock

import (
	"context"

	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/proto"
)

type MockedHydroPublisher struct {
	mock.Mock
}

func (m *MockedHydroPublisher) Publish(ctx context.Context, msg proto.Message) error {
	args := m.Called(ctx, msg)
	return args.Error(0)
}

func (m *MockedHydroPublisher) Close() error {
	args := m.Called()
	return args.Error(0)
}
