package mock

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/mock"
)

type MockedDependabotEventService struct {
	mock.Mock
}

func (m *MockedDependabotEventService) CheckRepositoryReadiness(ctx context.Context, repositoryID uint64, eventType *interfaces.EventType) (*interfaces.ReadinessResult, *interfaces.DependabotEvent, error) {
	args := m.Called(ctx, repositoryID, eventType)
	result, _ := args.Get(0).(*interfaces.ReadinessResult)
	event, _ := args.Get(1).(*interfaces.DependabotEvent)
	return result, event, args.Error(2)
}

func (m *MockedDependabotEventService) CheckEventReadiness(ctx context.Context, eventID uint64) (*interfaces.ReadinessResult, error) {
	args := m.Called(ctx, eventID)
	return args.Get(0).(*interfaces.ReadinessResult), args.Error(1)
}

func (m *MockedDependabotEventService) RecordDependabotEvent(ctx context.Context, repositoryID uint64, eventType interfaces.EventType, ref string, sha string, pushID *uint64, entries []interfaces.DependabotRequestedSnapshot) (uint64, error) {
	args := m.Called(ctx, repositoryID, eventType, ref, sha, pushID, entries)
	return args.Get(0).(uint64), args.Error(1)
}

func (m *MockedDependabotEventService) MarkSnapshotReceived(ctx context.Context, eventID uint64, snapshotID uint64, ecosystem ecosystems.Ecosystem, manifestPath string) (bool, error) {
	args := m.Called(ctx, eventID, snapshotID, ecosystem, manifestPath)
	return args.Bool(0), args.Error(1)
}

func (m *MockedDependabotEventService) GetEventDeadline(ctx context.Context, eventID uint64) (time.Time, bool, error) {
	args := m.Called(ctx, eventID)
	return args.Get(0).(time.Time), args.Bool(1), args.Error(2)
}
