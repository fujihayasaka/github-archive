package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_addDedup(t *testing.T) {
	type args struct {
		slice []string
		elem  string
	}
	tests := []struct {
		name string
		args args
		want []string
	}{
		{
			name: "empty slice",
			args: args{
				slice: []string{},
				elem:  "foo",
			},
			want: []string{"foo"},
		},
		{
			name: "non repeated element",
			args: args{
				slice: []string{"a", "b", "c"},
				elem:  "d",
			},
			want: []string{"a", "b", "c", "d"},
		},
		{
			name: "repeated element",
			args: args{
				slice: []string{"a", "b", "c"},
				elem:  "b",
			},
			want: []string{"a", "b", "c"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, addDedup(tt.args.slice, tt.args.elem), "addDedup(%v, %v)", tt.args.slice, tt.args.elem)
		})
	}
}

func TestPullRequestConversion(t *testing.T) {
	body := "pr body"
	resourceID := "http://github.test/test-org/test-repo/pulls/2"
	user := "http://github.test/monalisa"
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	assignees := []string{"http://github.test/alice", "http://github.test/bob"}
	reactions := []Reaction{
		{
			Content:     "+1",
			SubjectType: "pull_request",
			User:        user,
			CreatedAt:   someTime,
		},
		{
			Content:     "+1",
			SubjectType: "pull_request",
			User:        user,
			CreatedAt:   someTime,
		},
	}

	var reviewers []ReviewRequest
	// reuse assignees as reviewers
	for _, r := range assignees {
		reviewers = append(reviewers, ReviewRequest{
			Reviewer:     r,
			ReviewerType: "User",
		})
	}

	// Add a duplicate reviewer to the pr that we expect to not be in the result.
	// Add a non "User" reviewer to the pr that we expect is skipped.
	reviewers = append(reviewers, ReviewRequest{Reviewer: "http://github.test/bob"}, ReviewRequest{ReviewerType: "not-user"})
	ic := &PullRequest{
		Body:      body,
		CreatedAt: someTime,
		Reactions: reactions,
		Type:      "pull_request",
		URL:       resourceID,
		User:      user,
		// Add a duplicate assignee to the pr that we expect to not be in the result.
		Assignees:      append(assignees, "http://github.test/bob"),
		ReviewRequests: reviewers,
		WorkInProgress: true,
		Base: RefDetails{
			Ref: "branch",
			Sha: "123abc",
		},
		Head: RefDetails{
			Ref: "main",
			Sha: "foo456",
		},
		ClosedAt:       someTime,
		MergedAt:       someTime,
		MergeCommitSha: "xyz789",
	}

	expected := &v1.PullRequest{
		ResourceId:            resourceID,
		UserResourceId:        user,
		Body:                  body,
		CreatedAt:             toTimestamp(someTime),
		AssigneesResourceIds:  assignees,
		ReviewersResourceIds:  assignees,
		AttachmentResourceIds: nil,
		IsDraft:               ic.WorkInProgress,
		BaseRef: &v1.RefDetails{
			Name:      ic.Base.Ref,
			CommitSha: ic.Base.Sha,
		},
		HeadRef: &v1.RefDetails{
			Name:      ic.Head.Ref,
			CommitSha: ic.Head.Sha,
		},
		ClosedAt:       toTimestamp(ic.ClosedAt),
		MergedAt:       toTimestamp(ic.MergedAt),
		MergeCommitSha: ic.MergeCommitSha,
	}

	v1c, err := ic.ToV1PullRequest()
	require.NoError(t, err)
	require.Equal(t, expected, v1c)
}

func TestPullRequestIsFromFork(t *testing.T) {
	type testCase struct {
		pr       *PullRequest
		expected bool
	}
	cases := map[string]*testCase{
		"NotForked": {
			pr: &PullRequest{
				Base: RefDetails{
					Ref: "main",
				},
				Head: RefDetails{
					Ref: "feature",
				},
			},
			expected: false,
		},
		"ForkedBase": {
			pr: &PullRequest{
				Base: RefDetails{
					Ref: "repo:main",
				},
				Head: RefDetails{
					Ref: "feature",
				},
			},
			expected: true,
		},
		"ForkedHead": {
			pr: &PullRequest{
				Base: RefDetails{
					Ref: "main",
				},
				Head: RefDetails{
					Ref: "repo:feature",
				},
			},
			expected: true,
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			fork := tc.pr.IsFromFork()
			require.Equal(t, tc.expected, fork)
		})
	}
}

func TestExtractCloseIssueReferences(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	pullURL := "http://github.test/test-org/test-repo/pulls/2"
	ic := &PullRequest{
		URL: pullURL,
		CloseIssueReferences: []CloseIssueReference{
			{
				Issue:           "http://github.test/test-org/test-repo/issues/3",
				IssueRepository: "http://github.test/test-org/test-repo",
				Actor:           "http://github.test/monalisa",
				Source:          "xref",
				CreatedAt:       someTime,
			},
			{
				Issue:           "http://github.test/test-org/test-repo/issues/4",
				IssueRepository: "http://github.test/test-org/test-repo",
				Actor:           "http://github.test/lonamisa",
				Source:          "xref",
				CreatedAt:       someTime,
			},
		},
	}
	refs := ic.ExtractV1CloseIssueReferences()
	require.Len(t, refs, 2)
	for _, r := range refs {
		assert.Equal(t, pullURL, r.PullRequestResourceId)
	}
}

func TestPrepareCloseIssueReferenceBatches(t *testing.T) {
	testCases := []struct {
		name            string
		references      []*v1.CloseIssueReference
		batchSize       int
		expectedBatches int
		expectError     bool
	}{
		{
			name:            "Normal case, multiple batches",
			references:      []*v1.CloseIssueReference{{}, {}, {}, {}, {}},
			batchSize:       2,
			expectedBatches: 3, // 5 references, 2 per batch = 3 batches
		},
		{
			name:            "Empty references list",
			references:      []*v1.CloseIssueReference{},
			batchSize:       2,
			expectedBatches: 0,
		},
		{
			name:            "Batch size larger than references",
			references:      []*v1.CloseIssueReference{{}, {}},
			batchSize:       10,
			expectedBatches: 1, // All references in one batch
		},
		{
			name:            "Invalid batch size (zero)",
			references:      []*v1.CloseIssueReference{{}, {}},
			batchSize:       0,
			expectedBatches: 0,
		},
		{
			name:            "Exact batch size",
			references:      []*v1.CloseIssueReference{{}, {}, {}},
			batchSize:       3,
			expectedBatches: 1,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			batches := prepareCloseIssueReferenceBatches(tc.references, tc.batchSize)
			assert.Equal(t, tc.expectedBatches, len(batches))
			for _, b := range batches {
				assert.NotEmpty(t, b.ResourceId)
			}
		})
	}
}
