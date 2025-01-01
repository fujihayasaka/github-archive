package workflowinvoker

import (
	"testing"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"

	"github.com/stretchr/testify/require"

	githubgo "github.com/google/go-github/v25/github"
)

func Test_isSkippablePushOrPullRequest(t *testing.T) {
	var nullSha = string(types.NullCommitSha)

	tests := []struct {
		name  string
		input Invocation
		want  bool
	}{
		{
			name: "push",
			input: Invocation{Event: InvokingEvent{
				Name: flowevents.Push,
				Ghe:  &githubgo.PushEvent{},
			}},
			want: true,
		},
		{
			name: "pull_request",
			input: Invocation{Event: InvokingEvent{
				Name: flowevents.PullRequest,
				Ghe:  &githubgo.PullRequestEvent{},
			}},
			want: true,
		},
		{
			name: "pull_request_target",
			input: Invocation{Event: InvokingEvent{
				Name: flowevents.PullRequestTarget,
				Ghe:  &githubgo.PullRequestEvent{},
			}},
			want: false,
		},
		{
			name: "push that's actually a delete",
			input: Invocation{Event: InvokingEvent{
				Name: flowevents.Push,
				Ghe: &githubgo.PushEvent{
					After: &nullSha,
				},
			}},
			want: false,
		},
		{
			name: "not a push or pull_request",
			input: Invocation{Event: InvokingEvent{
				Name: flowevents.WorkflowDispatch,
				Ghe:  &githubgo.WorkflowDispatchEvent{},
			}},
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isSkippablePushOrPullRequest(tt.input)
			require.Equal(t, tt.want, got)
		})
	}
}

func Test_hasSkipRunAnnotation(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  bool
	}{
		{
			name: "base case",
			input: `this commit should not trigger a workflow


skip-checks: true`,
			want: true,
		},
		{
			name:  "base case - missing space before true",
			input: "this commit should not trigger a workflow\n\n\nskip-checks:true",
			want:  true,
		},
		{
			name:  "trailing whitespace, missing space before 'true'",
			input: "this commit should not trigger a workflow\n\n\nskip-checks: true\n",
			want:  true,
		},
		{
			name:  "trailing whitespace, missing space before 'true'",
			input: "this commit should not trigger a workflow\n\n\nskip-checks:true\n",
			want:  true,
		},
		{
			name:  "windows newlines",
			input: "this commit should not trigger a workflow\r\n\r\n\r\nskip-checks: true",
			want:  true,
		},
		{
			name:  "windows newlines - trailing",
			input: "this commit should not trigger a workflow\r\n\r\n\r\nskip-checks: true\r\n",
			want:  true,
		},
		{
			name:  "extra newlines",
			input: "this commit should not trigger a workflow\n\n\n\n\n\n\n\nskip-checks: true\n",
			want:  true,
		},
		{
			name:  "keyword [skip ci] located anywhere",
			input: "this commit with [skip ci] in it should not trigger a workflow",
			want:  true,
		},
		{
			name:  "keyword [ci skip] located anywhere",
			input: "this commit with [ci skip] in it should not trigger a workflow",
			want:  true,
		},
		{
			name:  "keyword [no ci] located anywhere",
			input: "this commit with [no ci] in it should not trigger a workflow",
			want:  true,
		},
		{
			name:  "keyword [skip actions] located anywhere",
			input: "this commit with [skip actions] in it should not trigger a workflow",
			want:  true,
		},
		{
			name:  "keyword [actions skip] located anywhere",
			input: "this commit with [actions skip] in it should not trigger a workflow",
			want:  true,
		},
		{
			name:  "skip checks false",
			input: "this commit should not trigger a workflow\n\n\nskip-checks: false",
			want:  false,
		},
		{
			name:  "unbracketed keyword 'skip ci' located anywhere",
			input: "this commit with skip ci in it should not trigger a workflow",
			want:  false,
		},
		{
			name:  "unbracketed keyword 'ci skip' located anywhere",
			input: "this commit with ci skip in it should not trigger a workflow",
			want:  false,
		},
		{
			name:  "unbracketed keyword 'no ci' located anywhere",
			input: "this commit with no ci in it should not trigger a workflow",
			want:  false,
		},
		{
			name:  "unbracketed keyword 'skip actions' located anywhere",
			input: "this commit with skip actions in it should not trigger a workflow",
			want:  false,
		},
		{
			name:  "unbracketed keyword 'actions skip' located anywhere",
			input: "this commit with actions skip in it should not trigger a workflow",
			want:  false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := hasSkipRunAnnotation(types.CommitMessage(tt.input))
			require.Equalf(t, tt.want, got, "commit message: %q", tt.input)
		})
	}
}
