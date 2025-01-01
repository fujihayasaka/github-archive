package flowevents_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
)

func TestExtraction(t *testing.T) {
	cases := []struct {
		eventType       string
		fixture         string // only needed if it's different from eventType
		expectedSha     types.CommitSha
		expectedRef     types.GitRef
		expectedOk      bool
		expectedMessage types.CommitMessage
	}{
		{
			eventType:   "branch_protection_rule",
			expectedSha: types.CommitShaZeroValue,
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "check_run",
			expectedSha: types.CommitShaZeroValue, // Untrusted event SHA
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "check_suite",
			expectedSha: types.CommitShaZeroValue, // Untrusted event SHA
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "create",
			expectedSha: types.CommitShaZeroValue,
			// TODO type can be repository, branch and tag
			expectedRef: types.GitRef("refs/tags/simple-tag"),
			expectedOk:  true,
		},
		{
			eventType:   "delete",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "deployment",
			expectedSha: types.CommitSha("a10867b14bb761a232cd80139fbd4c0d33264240"),
			expectedRef: types.GitRef("master"),
			expectedOk:  true,
		},
		{
			eventType:   "deployment_status",
			expectedSha: types.CommitSha("a10867b14bb761a232cd80139fbd4c0d33264240"),
			expectedRef: types.GitRefZeroValue,
			expectedOk:  true,
		},
		{
			eventType:   "discussion",
			expectedSha: types.CommitShaZeroValue,
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "discussion_comment",
			expectedSha: types.CommitShaZeroValue,
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "fork",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "gollum",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "issue_comment",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "issues",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "label",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "member",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "milestone",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "registry_package",
			expectedSha: types.CommitSha("b3156b05a2e7a0f8fd11deac6999732a229bd3ad"),
			expectedRef: types.GitRef("master"),
			expectedOk:  true,
		},
		{
			eventType:   "page_build",
			expectedSha: types.CommitShaZeroValue, // Untrusted event SHA
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "project",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "project_card",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "project_column",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "public",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "pull_request",
			expectedSha: types.CommitSha("34c5c7793cb3b279e22454cb6750c80560547b3a"),
			expectedRef: types.GitRef("refs/heads/changes"),
			expectedOk:  true,
		},
		{
			eventType:   "pull_request",
			fixture:     "pull_request-from-fork",
			expectedSha: types.CommitSha("ab3b10ce24896b0287db2529eae950ac53245cae"),
			expectedRef: types.GitRef("refs/heads/master"),
			expectedOk:  true,
		},
		{
			eventType:   "pull_request_review",
			expectedSha: types.CommitSha("34c5c7793cb3b279e22454cb6750c80560547b3a"),
			expectedRef: types.GitRef("refs/heads/changes"),
			expectedOk:  true,
		},
		{
			eventType:   "pull_request_review_comment",
			expectedSha: types.CommitSha("34c5c7793cb3b279e22454cb6750c80560547b3a"),
			expectedRef: types.GitRef("refs/heads/changes"),
			expectedOk:  true,
		},
		{
			eventType:       "push",
			expectedSha:     types.CommitSha("289345eeab3bfbf8a1651f9668cf5ca04dffa550"),
			expectedRef:     types.GitRef("refs/heads/master"),
			expectedMessage: types.CommitMessage("test-e2e commit from build version 2a9c2286514691322691606c3c24a45c5b4136db"),
			expectedOk:      true,
		},
		{
			eventType:       "push",
			fixture:         "push-annotated-tag",
			expectedSha:     types.CommitSha("afd013283ae32f41428f0bc2b335064f6223e977"),
			expectedMessage: types.CommitMessage("foo"),
			expectedRef:     types.GitRef("refs/tags/bar"),
			expectedOk:      true,
		},
		{
			eventType:   "push",
			fixture:     "push_nil_head_commit",
			expectedSha: types.CommitShaZeroValue,
			expectedRef: types.GitRefZeroValue,
			expectedOk:  false,
		},
		{
			eventType:   "push",
			fixture:     "push-delete",
			expectedSha: types.CommitShaZeroValue,
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "repository_dispatch",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		// TODO Repository vulnerability alert is missing from go-github
		// {
		// 	eventType:       "repository_vulnerability_alert",
		// 	expectedSha:     types.NilCommitSha,  // no sha included in the event
		// 	expectedRef:     types.DefaultBranch, // branch not available but needs resolving
		// },
		{
			eventType:   "release",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.NewTagRef("0.0.1"),
			expectedOk:  true,
		},
		{
			eventType:   "status",
			expectedSha: types.CommitShaZeroValue, // Untrusted event SHA
			expectedRef: types.DefaultBranch,
			expectedOk:  true,
		},
		{
			eventType:   "watch",
			expectedSha: types.CommitShaZeroValue, // no sha included in the event
			expectedRef: types.DefaultBranch,      // branch not available but needs resolving
			expectedOk:  true,
		},
		{
			eventType:   "pull_request_target",
			expectedSha: types.CommitSha("34c5c7793cb3b279e22454cb6750c80560547b3a"),
			expectedRef: types.GitRef("refs/heads/changes"),
			expectedOk:  true,
		},
		{
			eventType:   "merge_group",
			expectedSha: types.CommitSha("52ff80b7280ead5a3b925ebcfe7a6f09a8effac2"),
			expectedRef: types.GitRef("refs/gh/queue/master/pr-1-cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"),
			expectedOk:  true,
		},
	}

	readFixture := func(fixture, eventType string) ([]byte, error) {
		if len(fixture) == 0 {
			fixture = eventType
		}
		return os.ReadFile(filepath.Join("fixtures", fixture+".json"))
	}

	for index, tc := range cases {
		t.Run(tc.eventType, func(tt *testing.T) {
			payload, err := readFixture(tc.fixture, tc.eventType)
			require.NoError(tt, err)
			event, err := flowevents.ParseEventWebHook(flowevents.ResolveSyntheticEventName(tc.eventType), payload)
			require.NoError(tt, err)
			sha, ref, ok, err := flowevents.ExtractCommitAndRef(tc.eventType, event)
			require.NoError(tt, err)

			message := flowevents.ExtractCommitMessage(event)

			msg := fmt.Sprintf("test #%d failed, event type %s", index, tc.eventType)
			require.Equal(tt, tc.expectedOk, ok)
			require.Equal(tt, tc.expectedSha, sha, msg)
			require.Equal(tt, tc.expectedRef, ref, msg)
			require.Equal(tt, tc.expectedMessage, message, msg)
		})
	}
}

func TestPushedAtExtraction(t *testing.T) {
	now := time.Now()
	zero := time.Time{}

	cases := []struct {
		eventType string
		event     any
		expected  time.Time
	}{
		// https://github.com/github/project-everett/blob/master/docs/events.md
		{
			eventType: "check_run",
			event: &github.CheckRunEvent{
				CheckRun: &github.CheckRun{
					CheckSuite: &github.CheckSuite{
						HeadBranch: github.String("my-awesome-feature"),
					},
				},
			},
			expected: zero,
		},
		{
			eventType: "push",
			event: &github.PushEvent{
				Repo: &github.PushEventRepository{
					PushedAt: &github.Timestamp{Time: now},
				},
			},
			expected: now,
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.eventType, func(tt *testing.T) {
			pushedAt := flowevents.ExtractEventTime(testCase.eventType, testCase.event)
			assert.Equal(tt, testCase.expected, pushedAt)
		})
	}

}

func TestDynamicExtraction(t *testing.T) {
	commit, ref, ok, err := flowevents.ExtractCommitAndRef(flowevents.Dynamic, &flowevents.DynamicEvent{
		Ref:      "refs/heads/main",
		Workflow: "some workflow",
	})

	require.NoError(t, err)
	assert.Equal(t, types.CommitShaZeroValue, commit)
	assert.Equal(t, types.GitRef("refs/heads/main"), ref)
	assert.Equal(t, true, ok)
}
