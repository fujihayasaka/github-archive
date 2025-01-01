package cmd

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/servermigrator"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestWALTarget_buildProcessBatch(t *testing.T) {
	logger := log.NewNullLogger()
	maxSendBatchSize = 1

	type args struct {
		events []*v1.WALEvent
	}
	tests := []struct {
		name            string
		setupTargetMock func(*servermigrator.MockMigrationTargetAPI)
		args            args
		wantErr         assert.ErrorAssertionFunc
	}{
		{
			name: "should process events in two batches of one event each",
			setupTargetMock: func(target *servermigrator.MockMigrationTargetAPI) {
				target.On(
					"SendEvents",
					mock.Anything,
					"",
					[]*v1.Event{{EventId: "1"}},
				).Return(nil)
				target.On(
					"SendResources",
					mock.Anything,
					"",
					[]*v1.Resource{{Resource: &v1.Resource_Noop{Noop: &v1.Noop{ResourceId: "1"}}}},
				).Return(nil)
				target.On(
					"SendEvents",
					mock.Anything,
					"",
					[]*v1.Event{{EventId: "2"}},
				).Return(nil)
				target.On(
					"SendResources",
					mock.Anything,
					"",
					[]*v1.Resource{{Resource: &v1.Resource_Noop{Noop: &v1.Noop{ResourceId: "2"}}}},
				).Return(nil)
			},
			args: args{
				events: []*v1.WALEvent{
					{
						Events: []*v1.Event{
							{
								EventId: "1",
							},
						},
						Resources: []*v1.Resource{
							{
								Resource: &v1.Resource_Noop{
									Noop: &v1.Noop{ResourceId: "1"},
								},
							},
						},
					},
					{
						Events: []*v1.Event{
							{
								EventId: "2",
							},
						},
						Resources: []*v1.Resource{
							{
								Resource: &v1.Resource_Noop{
									Noop: &v1.Noop{ResourceId: "2"},
								},
							},
						},
					},
				},
			},
			wantErr: assert.NoError,
		},
		{
			name: "should retry on error",
			setupTargetMock: func(target *servermigrator.MockMigrationTargetAPI) {
				target.On(
					"SendEvents",
					mock.Anything,
					"",
					[]*v1.Event{{EventId: "1"}},
				).Return(assert.AnError).Times(3)
				target.On(
					"SendEvents",
					mock.Anything,
					"",
					[]*v1.Event{{EventId: "1"}},
				).Return(nil)
			},
			args: args{
				events: []*v1.WALEvent{
					{
						Events: []*v1.Event{
							{
								EventId: "1",
							},
						},
					},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			target := servermigrator.NewMockMigrationTargetAPI(t)
			tt.setupTargetMock(target)

			w := &WALTarget{
				target: target,
				logger: logger,
			}

			fn := w.buildProcessBatchFn(context.Background())

			if !tt.wantErr(t, fn(tt.args.events), "") {
				return
			}

			target.AssertExpectations(t)
		})
	}
}
