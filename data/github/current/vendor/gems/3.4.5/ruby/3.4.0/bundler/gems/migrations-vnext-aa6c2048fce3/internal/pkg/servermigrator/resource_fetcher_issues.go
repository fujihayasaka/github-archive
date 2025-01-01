package servermigrator

import (
	"context"
	"fmt"
	"iter"

	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	"github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
)

// issues returns a sequence of resources that represent the issues in the repository along with their authors.
func (r *ResourceFetcher) issues() iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		// fetchErr is used to propagate errors from the fetch functions that use iterators
		fetchErr := &FetchErr{}
		defer func() { r.err = fetchErr.Err() }()

		for issue := range r.fetchIssues(fetchErr) {
			if issue.IsPullRequest() {
				continue
			}

			i := googlegithub.Issue{Issue: *issue}

			user := googlegithub.User{User: *i.GetUser()}
			convU, err := user.ToV1Mannequin(r.org)
			if err != nil {
				r.err = fmt.Errorf("error converting issue author to User: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: convU}}) {
				return
			}

			conv, err := i.ToV1Issue()
			if err != nil {
				r.err = fmt.Errorf("error converting to v1.Issue: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Issue{Issue: conv}}) {
				return
			}

			// issue reactions
			for reaction := range r.issueReactions(conv.ResourceId, i.GetNumber(), fetchErr) {
				if !yield(reaction) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}

			// issue comments
			for resource := range r.issueComments(i.GetNumber(), fetchErr) {
				if !yield(resource) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}
		}
	}
}

// issueReactions returns a sequence of resources that represent the reactions on a given issue.
func (r *ResourceFetcher) issueReactions(issueID string, number int, fetchErr *FetchErr) iter.Seq[*v1.Resource] {
	return r.reactionBatcher(r.fetchIssueReactions(number, fetchErr), v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE, issueID)
}

// issueComments returns a sequence of resources that represent the issue comments in a given issue along with their authors.
func (r *ResourceFetcher) issueComments(number int, fetchErr *FetchErr) iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		for comment := range r.fetchIssueComments(number, fetchErr) {
			i := googlegithub.IssueComment{IssueComment: *comment}

			user := googlegithub.User{User: *i.GetUser()}
			convU, err := user.ToV1Mannequin(r.org)
			if err != nil {
				r.err = fmt.Errorf("error converting issue comment author to User: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: convU}}) {
				return
			}

			conv, err := i.ToV1IssueComment()
			if err != nil {
				r.err = fmt.Errorf("error converting to v1.IssueComment: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_IssueComment{IssueComment: conv}}) {
				return
			}

			// issue comment reactions
			for reaction := range r.issueCommentReactions(comment.GetID(), conv.ResourceId, fetchErr) {
				if !yield(reaction) {
					return
				}
			}
			if fetchErr.Err() != nil {
				return
			}
		}
	}
}

// issueCommentReactions returns a sequence of resources that represent the reactions on a given issue comment.
func (r *ResourceFetcher) issueCommentReactions(id int64, subjectID string, fetchErr *FetchErr) iter.Seq[*v1.Resource] {
	return r.reactionBatcher(r.fetchIssueCommentReactions(id, fetchErr), v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE_COMMENT, subjectID)
}

// issuesIterBuilder returns a function that builds an iterator for fetching all issues in a repository using the given GitHub client.
func issuesIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchIssues {
	return func(err *FetchErr) iter.Seq[*ogithub.Issue] {
		scanner := NewScanner[*ogithub.Issue](c, defaultPerPage)
		defer func() { err.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.Issue, *ogithub.Response, error) {
			opts := &ogithub.IssueListByRepoOptions{
				Direction:   "asc",
				ListOptions: listOptions,
				Sort:        "created",
				State:       "all",
			}
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.Issues.ListByRepo(rlCtx, owner, repo, opts)
		})
	}
}

// issueCommentsIterBuilder returns a function that builds an iterator for fetching all issue comments in an issue using the given GitHub client.
func issueCommentsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchIssueComments {
	return func(number int, err *FetchErr) iter.Seq[*ogithub.IssueComment] {
		scanner := NewScanner[*ogithub.IssueComment](c, defaultPerPage)
		defer func() { err.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.IssueComment, *ogithub.Response, error) {
			opts := &ogithub.IssueListCommentsOptions{
				ListOptions: listOptions,
				Sort:        pointer.Of("created"),
			}
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.Issues.ListComments(rlCtx, owner, repo, number, opts)
		})
	}
}

// issueReactionsIterBuilder returns a function that builds an iterator for fetching all reactions on an issue using the given GitHub client.
func issueReactionsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchIssueReactions {
	return func(number int, fetchErr *FetchErr) iter.Seq[*ogithub.Reaction] {
		scanner := NewScanner[*ogithub.Reaction](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.Reaction, *ogithub.Response, error) {
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.Reactions.ListIssueReactions(rlCtx, owner, repo, number, &listOptions)
		})
	}
}

// issueCommentReactionsIterBuilder returns a function that builds an iterator for fetching all reactions on an issue comment using the given GitHub client.
func issueCommentReactionsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) fetchIssueCommentReactions {
	return func(id int64, fetchErr *FetchErr) iter.Seq[*ogithub.Reaction] {
		scanner := NewScanner[*ogithub.Reaction](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.Reaction, *ogithub.Response, error) {
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.Reactions.ListIssueCommentReactions(rlCtx, owner, repo, id, &listOptions)
		})
	}
}
