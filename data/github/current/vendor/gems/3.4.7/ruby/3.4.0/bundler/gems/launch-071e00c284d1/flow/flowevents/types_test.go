package flowevents

import (
	"fmt"
	"reflect"
	"testing"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
)

func TestIsRestrictedForkPREvent(t *testing.T) {
	headID := int64(1)
	baseID := int64(2)
	nonForkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &headID,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &headID,
			},
		},
	}

	forkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &headID,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &baseID,
			},
		},
	}

	testCases := []struct {
		name           string
		eventName      string
		events         []GitHubEvent
		expectedResult bool
	}{
		{
			"push",
			Push,
			[]GitHubEvent{
				&githubgo.PushEvent{},
			},
			false,
		},
		{
			"pull_request event for non-fork PR",
			PullRequest,
			[]GitHubEvent{
				&githubgo.PullRequestEvent{PullRequest: nonForkPR},
			},
			false,
		},
		{
			"pull_request_review event for non-fork PR",
			PullRequestReview,
			[]GitHubEvent{
				&githubgo.PullRequestReviewEvent{PullRequest: nonForkPR},
			},
			false,
		},
		{
			"pull_request_review_comment event for non-fork PR",
			PullRequestReviewComment,
			[]GitHubEvent{
				&githubgo.PullRequestReviewCommentEvent{PullRequest: nonForkPR},
			},
			false,
		},
		{
			"pull_request event for fork PR",
			PullRequest,
			[]GitHubEvent{
				&githubgo.PullRequestEvent{PullRequest: forkPR},
			},
			true,
		},
		{
			"pull_request_review event for fork PR",
			PullRequestReview,
			[]GitHubEvent{
				&githubgo.PullRequestReviewEvent{PullRequest: forkPR},
			},
			true,
		},
		{
			"pull_request_review_comment event for fork PR",
			PullRequestReviewComment,
			[]GitHubEvent{
				&githubgo.PullRequestReviewCommentEvent{PullRequest: forkPR},
			},
			true,
		},
		{
			"pull_request_target events",
			PullRequestTarget,
			[]GitHubEvent{
				&githubgo.PullRequestEvent{PullRequest: nonForkPR},
				&githubgo.PullRequestReviewEvent{PullRequest: nonForkPR},
				&githubgo.PullRequestReviewCommentEvent{PullRequest: nonForkPR},
				&githubgo.PullRequestEvent{PullRequest: forkPR},
				&githubgo.PullRequestReviewEvent{PullRequest: forkPR},
				&githubgo.PullRequestReviewCommentEvent{PullRequest: forkPR},
			},
			false,
		},
	}

	for _, tc := range testCases {
		if len(tc.events) == 0 {
			panic("no events supplied")
		}

		for _, event := range tc.events {
			t.Run(fmt.Sprintf("%v (event: %v)", tc.name, reflect.TypeOf(event)), func(t *testing.T) {
				assert.Equal(t, tc.expectedResult, IsRestrictedForkPREvent(tc.eventName, event))
			})
		}
	}
}

func TestPullRequestAuthorEligible(t *testing.T) {
	events := []struct {
		association string
		eligible    bool
	}{
		{string(githubv4.CommentAuthorAssociationMember), true},
		{string(githubv4.CommentAuthorAssociationOwner), true},
		{string(githubv4.CommentAuthorAssociationCollaborator), true},
		{string(githubv4.CommentAuthorAssociationContributor), true},
		{"other association", false},
		{"", false},
	}

	for _, event := range events {
		assert.Equal(t, event.eligible, PullRequestAuthorEligible(event.association),
			fmt.Sprintf("Author association '%q' workflow eligibility incorrect", event.association))
	}
}

func TestIsForkPR(t *testing.T) {
	repositoryA := int64(1)
	repositoryB := int64(2)
	nonForkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &repositoryA,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &repositoryA,
			},
		},
	}

	forkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &repositoryA,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &repositoryB,
			},
		},
	}
	type args struct {
		pr HasPullRequest
	}
	tests := []struct {
		name string
		args args
		want bool
	}{
		{
			"fork",
			args{
				&githubgo.PullRequestEvent{PullRequest: forkPR},
			},
			true,
		},
		{
			"not fork",
			args{
				&githubgo.PullRequestEvent{PullRequest: nonForkPR},
			},
			false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsForkPR(tt.args.pr); got != tt.want {
				t.Errorf("IsForkPR() = %v, want %v", got, tt.want)
			}
		})
	}
}
