package github

import (
	"context"
	"testing"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBranchNameFromHeadRef(t *testing.T) {
	tests := []struct {
		name     string
		headRef  string
		expected string
	}{
		{
			name:     "plain branch name returned as-is",
			headRef:  "feature-branch",
			expected: "feature-branch",
		},
		{
			name:     "fork owner:branch returns branch only",
			headRef:  "john:feature-x",
			expected: "feature-x",
		},
		{
			name:     "fork owner:branch with slashes",
			headRef:  "john:fix/issue-123",
			expected: "fix/issue-123",
		},
		{
			name:     "malformed owner: returns original",
			headRef:  "owner:",
			expected: "owner:",
		},
		{
			name:     "malformed :branch returns original",
			headRef:  ":branch",
			expected: ":branch",
		},
		{
			name:     "empty string returns empty",
			headRef:  "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := BranchNameFromHeadRef(tt.headRef)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestIsForkHeadRef(t *testing.T) {
	tests := []struct {
		name     string
		headRef  string
		expected bool
	}{
		{
			name:     "plain branch is not fork",
			headRef:  "feature-branch",
			expected: false,
		},
		{
			name:     "owner:branch is fork",
			headRef:  "john:feature-x",
			expected: true,
		},
		{
			name:     "owner: without branch is not fork",
			headRef:  "owner:",
			expected: false,
		},
		{
			name:     ":branch without owner is not fork",
			headRef:  ":branch",
			expected: false,
		},
		{
			name:     "empty string is not fork",
			headRef:  "",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isForkHeadRef(tt.headRef)
			assert.Equal(t, tt.expected, got)
		})
	}
}

// mockGHClient implements the GetPullRequests method for LookupExistingPRForHeadRef tests.
type mockGHClient struct {
	ClientInterface
	getPullRequestsFn func(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error)
}

func (m *mockGHClient) GetPullRequests(ctx context.Context, owner, repo string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error) {
	return m.getPullRequestsFn(ctx, owner, repo, opts)
}

func TestLookupExistingPRForHeadRef(t *testing.T) {
	tests := []struct {
		name            string
		owner           string
		repo            string
		headRef         string
		baseRef         string
		prs             []*gg.PullRequest
		expectedHead    string // the Head filter passed to GetPullRequests
		expectPR        bool
		expectAmbiguity bool
	}{
		{
			name:    "same-repo PR: prepends owner to headRef",
			owner:   "dotnet",
			repo:    "runtime",
			headRef: "feature-branch",
			baseRef: "main",
			prs: []*gg.PullRequest{
				{Base: &gg.PullRequestBranch{Ref: gg.Ptr("main")}},
			},
			expectedHead: "dotnet:feature-branch",
			expectPR:     true,
		},
		{
			name:    "fork PR: uses owner:branch directly",
			owner:   "dotnet",
			repo:    "runtime",
			headRef: "john:feature-x",
			baseRef: "main",
			prs: []*gg.PullRequest{
				{Base: &gg.PullRequestBranch{Ref: gg.Ptr("main")}},
			},
			expectedHead: "john:feature-x",
			expectPR:     true,
		},
		{
			name:         "no matching PRs: returns nil",
			owner:        "dotnet",
			repo:         "runtime",
			headRef:      "john:feature-x",
			baseRef:      "main",
			prs:          []*gg.PullRequest{},
			expectedHead: "john:feature-x",
			expectPR:     false,
		},
		{
			name:    "base ref mismatch: returns nil with ambiguity",
			owner:   "dotnet",
			repo:    "runtime",
			headRef: "john:feature-x",
			baseRef: "main",
			prs: []*gg.PullRequest{
				{Base: &gg.PullRequestBranch{Ref: gg.Ptr("develop")}},
			},
			expectedHead:    "john:feature-x",
			expectPR:        false,
			expectAmbiguity: true,
		},
		{
			name:    "malformed headRef: falls back to owner prefix",
			owner:   "dotnet",
			repo:    "runtime",
			headRef: "owner:",
			baseRef: "main",
			prs: []*gg.PullRequest{
				{Base: &gg.PullRequestBranch{Ref: gg.Ptr("main")}},
			},
			expectedHead: "dotnet:owner:",
			expectPR:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var capturedHead string
			mock := &mockGHClient{
				getPullRequestsFn: func(_ context.Context, _, _ string, opts *gg.PullRequestListOptions) ([]*gg.PullRequest, error) {
					capturedHead = opts.Head
					return tt.prs, nil
				},
			}

			pr, ambiguity, err := LookupExistingPRForHeadRef(context.Background(), mock, tt.owner, tt.repo, tt.headRef, tt.baseRef)
			require.NoError(t, err)
			assert.Equal(t, tt.expectedHead, capturedHead, "Head filter passed to GitHub API")

			if tt.expectPR {
				assert.NotNil(t, pr)
			} else {
				assert.Nil(t, pr)
			}
			assert.Equal(t, tt.expectAmbiguity, ambiguity)
		})
	}
}
