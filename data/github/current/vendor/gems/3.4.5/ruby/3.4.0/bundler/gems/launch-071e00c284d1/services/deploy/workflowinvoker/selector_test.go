package workflowinvoker

import (
	"reflect"
	"testing"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
)

func TestNewWorkflowSelector(t *testing.T) {
	var ref = "refs/heads/main"
	var workflowPath = ".github/workflows/test.yml"

	type args struct {
		eventName string
		event     any
	}
	tests := []struct {
		name string
		args args
		want WorkflowSelector
	}{
		{
			name: "sets path for workflow_dispatch event",
			args: args{
				eventName: flowevents.WorkflowDispatch,
				event:     &githubgo.WorkflowDispatchEvent{Ref: &ref, Workflow: &workflowPath},
			},
			want: WorkflowSelector{EventName: flowevents.WorkflowDispatch, Path: &workflowPath},
		},
		{
			name: "sets event name for other events",
			args: args{
				eventName: flowevents.Push,
				event:     &githubgo.PushEvent{Ref: &ref},
			},
			want: WorkflowSelector{EventName: flowevents.Push, Path: nil},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := NewWorkflowSelector(tt.args.eventName, tt.args.event); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("selector() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestSelect(t *testing.T) {
	notExistantPath := ".github/workflows/some.yml"

	pushWorkflow := &model.Workflow{
		Identifier: "push",
		Path:       ".github/workflows/push.yml",
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
	}

	ciPushWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       ".github/workflows/ci.yml",
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
	}

	ciPullRequestWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       ".github/workflows/ci.yml",
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
	}

	schedule1RequestWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       ".github/workflows/schedule.yml",
		On: &model.OnSchedule{
			Expression: "*/5 * * * *",
		},
	}

	schedule2RequestWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       ".github/workflows/schedule.yml",
		On: &model.OnSchedule{
			Expression: "*/14 * * * *",
		},
	}

	scheduleLabelRequestWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       ".github/workflows/schedule.yml",
		On: &model.OnEvent{
			Event: flowevents.Label,
		},
	}

	workflowRunWorkflow := &model.Workflow{
		Identifier: "Collect workflow logs",
		Path:       ".github/workflows/collect-logs.yml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	workflows := &model.Configuration{
		Workflows: []*model.Workflow{
			pushWorkflow,
			ciPushWorkflow,
			ciPullRequestWorkflow,
			schedule1RequestWorkflow,
			schedule2RequestWorkflow,
			scheduleLabelRequestWorkflow,
			workflowRunWorkflow,
		},
	}

	tests := []struct {
		name     string
		selector WorkflowSelector
		expected []*model.Workflow
	}{
		{
			name: "Select by event - multiple",
			selector: WorkflowSelector{
				EventName: flowevents.Push,
			},
			expected: []*model.Workflow{
				pushWorkflow,
				ciPushWorkflow,
			},
		},
		{
			name: "Select by event - single",
			selector: WorkflowSelector{
				EventName: flowevents.PullRequest,
			},
			expected: []*model.Workflow{
				ciPullRequestWorkflow,
			},
		},
		{
			name: "Select by event - no match",
			selector: WorkflowSelector{
				EventName: flowevents.IssueComment,
			},
			expected: []*model.Workflow{},
		},
		{
			name: "Select by event and path",
			selector: WorkflowSelector{
				EventName: flowevents.Push,
				Path:      &pushWorkflow.Path,
			},
			expected: []*model.Workflow{
				pushWorkflow,
			},
		},
		{
			name: "Select by event and path - no match",
			selector: WorkflowSelector{
				EventName: flowevents.Push,
				Path:      &notExistantPath,
			},
			expected: []*model.Workflow{},
		},
		{
			name: "Select by single file - match single",
			selector: WorkflowSelector{
				EventName: flowevents.Schedule,
				Path:      &schedule1RequestWorkflow.Path,
			},
			expected: []*model.Workflow{
				schedule1RequestWorkflow,
			},
		},
		{
			name: "Select by single file - match single",
			selector: WorkflowSelector{
				EventName: flowevents.Label,
				Path:      &schedule1RequestWorkflow.Path,
			},
			expected: []*model.Workflow{
				scheduleLabelRequestWorkflow,
			},
		},
		{
			name: "Select by workflow",
			selector: WorkflowSelector{
				EventName: flowevents.WorkflowRun,
				Path:      &workflowRunWorkflow.Path,
			},
			expected: []*model.Workflow{
				workflowRunWorkflow,
			},
		},
		{
			name: "Select by dynamic event - all match",
			selector: WorkflowSelector{
				EventName: flowevents.Dynamic,
			},
			expected: workflows.Workflows,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result, err := test.selector.Select(workflows)
			require.NoError(t, err)
			assert.EqualValues(t, test.expected, result)
		})
	}
}
