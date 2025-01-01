package twirp

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestStoreEvent(t *testing.T) {
	tests := map[string]struct {
		request       *v1.StoreEventRequest
		setupMock     func(m *dag.MockManager)
		expectedError twirp.ErrorCode
	}{
		"should return invalid argument error for invalid event": {
			request: &v1.StoreEventRequest{
				Event: &v1.Event{
					ResourceId: "resource-123",
					Timestamp:  &timestamppb.Timestamp{Seconds: time.Now().Unix()},
				},
			},
			setupMock:     func(m *dag.MockManager) {},
			expectedError: twirp.InvalidArgument,
		},
		"should return an error when the manager returns an error": {
			request: &v1.StoreEventRequest{
				Event: &v1.Event{
					EventId:     "1",
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
					ResourceId:  "resource-123",
					Timestamp:   &timestamppb.Timestamp{Seconds: time.Now().Unix()},
				},
			},
			setupMock: func(m *dag.MockManager) {
				m.On("AddEvent", mock.IsType(context.Background()), mock.IsType(&v1.Event{})).Return(errors.New("test error"))
			},
			expectedError: twirp.Internal,
		},
		"should store event successfully": {
			request: &v1.StoreEventRequest{
				Event: &v1.Event{
					EventId:     "1",
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
					ResourceId:  "resource-123",
					Timestamp:   &timestamppb.Timestamp{Seconds: time.Now().Unix()},
				},
			},
			setupMock: func(m *dag.MockManager) {
				m.On("AddEvent", mock.IsType(context.Background()), &v1.Event{
					EventId:     "1",
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
					ResourceId:  "resource-123",
					Timestamp:   &timestamppb.Timestamp{Seconds: time.Now().Unix()},
				}).Return(nil)
			},
			expectedError: twirp.NoError,
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			mockManager := dag.NewMockManager(t)
			test.setupMock(mockManager)
			server := &Server{
				logger:  log.NewNullLogger(),
				manager: mockManager,
			}

			response, err := server.StoreEvent(context.Background(), test.request)
			if test.expectedError == twirp.NoError {
				require.NoError(t, err)
				assert.NotNil(t, response)
			} else {
				require.Error(t, err)
				var twerr twirp.Error
				ok := errors.As(err, &twerr)
				require.True(t, ok)
				assert.Equal(t, test.expectedError, twerr.Code())
			}
			mockManager.AssertExpectations(t)
		})
	}
}

func TestValidateEvent(t *testing.T) {
	someTime := time.Now()

	type args struct {
		e *v1.Event
	}
	tests := []struct {
		name    string
		args    args
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "valid event",
			args: args{
				e: &v1.Event{
					EventId:     "1",
					ResourceId:  "resource1",
					Timestamp:   timestamppb.New(someTime),
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				},
			},
			wantErr: assert.NoError,
		},
		{
			name: "nil event",
			args: args{
				e: nil,
			},
			wantErr: assert.Error,
		},
		{
			name: "missing event id",
			args: args{
				e: &v1.Event{
					ResourceId:  "resource1",
					Timestamp:   timestamppb.New(someTime),
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				},
			},
			wantErr: assert.Error,
		},
		{
			name: "missing resource id",
			args: args{
				e: &v1.Event{
					EventId:     "1",
					Timestamp:   timestamppb.New(someTime),
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				},
			},
			wantErr: assert.Error,
		},
		{
			name: "missing timestamp",
			args: args{
				e: &v1.Event{
					EventId:     "1",
					ResourceId:  "resource1",
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				},
			},
			wantErr: assert.Error,
		},
		{
			name: "missing event action",
			args: args{
				e: &v1.Event{
					EventId:    "1",
					ResourceId: "resource1",
					Timestamp:  timestamppb.New(someTime),
				},
			},
			wantErr: assert.Error,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.wantErr(t, validateEvent(tt.args.e), fmt.Sprintf("validateEvent(%v)", tt.args.e))
		})
	}
}
