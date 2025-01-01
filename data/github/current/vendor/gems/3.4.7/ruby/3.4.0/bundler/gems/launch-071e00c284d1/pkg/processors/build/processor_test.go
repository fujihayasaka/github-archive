package build

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/utils/ghtenant"
)

func Test_Processor_Process_GitHubTenant(t *testing.T) {
	tenantID := int64(123)
	tenantSlug := "tenant-slug"

	tests := []struct {
		name          string
		isMultiTenant bool
		gitHubTenant  ghtenant.GitHubTenant
		shouldError   bool
	}{
		{
			name: "non-multi-tenant/no-github-tenant",
		},
		{
			name: "non-multi-tenant/with-github-tenant",
			gitHubTenant: ghtenant.GitHubTenant{
				ID:   tenantID,
				Slug: tenantSlug,
			},
			shouldError: true,
		},
		{
			name: "multi-tenant/with-github-tenant",
			gitHubTenant: ghtenant.GitHubTenant{
				ID:   tenantID,
				Slug: tenantSlug,
			},
			isMultiTenant: true,
		},
		{
			name:          "multi-tenant/no-github-tenant",
			isMultiTenant: true,
			shouldError:   true,
		},
		{
			name: "multi-tenant/missing-tenant-id",
			gitHubTenant: ghtenant.GitHubTenant{
				Slug: tenantSlug,
			},
			isMultiTenant: true,
			shouldError:   true,
		},
		{
			name: "multi-tenant/missing-tenant-slug",
			gitHubTenant: ghtenant.GitHubTenant{
				ID: tenantID,
			},
			isMultiTenant: true,
			shouldError:   true,
		},
		{
			name: "multi-tenant/malformed-tenant-id",
			gitHubTenant: ghtenant.GitHubTenant{
				ID:   -1,
				Slug: tenantSlug,
			},
			isMultiTenant: true,
			shouldError:   true,
		},
		{
			name: "multi-tenant/empty-tenant-slug",
			gitHubTenant: ghtenant.GitHubTenant{
				ID:   tenantID,
				Slug: "",
			},
			isMultiTenant: true,
			shouldError:   true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			r := require.New(t)

			mockSlometricsReporter := &slometrics.MockHydroEmitter{}
			mockSlometricsReporter.EXPECT().EmitQueueRun(mock.Anything).Return()

			mockWorkflowInvoker := &workflowinvoker.MockInvoker{}
			mockWorkflowInvoker.On("Start",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return(nil).Run(func(args mock.Arguments) {
				inv := args.Get(2).(workflowinvoker.Invocation)
				r.EqualValues(test.gitHubTenant.ID, inv.Target.GitHubTenant.ID)
				r.EqualValues(test.gitHubTenant.Slug, inv.Target.GitHubTenant.Slug)
			})

			obs := observability.NewNullObservability()

			p := New(mockWorkflowInvoker, slometrics.New(mockSlometricsReporter), nil, test.isMultiTenant)

			messagePayload := Job{
				Invocation: workflowinvoker.Invocation{
					Event: workflowinvoker.InvokingEvent{
						Name: flowevents.ScheduleEventName,
					},
					Target: workflowinvoker.NewTarget("", 0, workflowinvoker.WorkflowSelector{}, "", 0, test.gitHubTenant),
				},
			}

			messagePayloadBytes, err := json.Marshal(&messagePayload)
			r.NoError(err)

			err = p.Process(context.Background(), obs, messagePayloadBytes, false)

			if test.shouldError {
				r.Error(err)
				return
			}

			r.NoError(err)
			mockWorkflowInvoker.AssertNumberOfCalls(t, "Start", 1)
		})
	}
}
