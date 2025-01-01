package servermigrator

import (
	"context"
	"fmt"
	"iter"

	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	"github.com/github/migrations-vnext/internal/pkg/github"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
)

// issues returns a sequence of resources that represent the commit comments belonging to a repo.
func (r *ResourceFetcher) commitComments() iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		// fetchErr is used to propagate errors from the fetch functions that use iterators
		fetchErr := &FetchErr{}
		defer func() { r.err = fetchErr.Err() }()

		for commitComment := range r.fetchAllCommitComments(fetchErr) {
			i := googlegithub.CommitComment{RepositoryComment: *commitComment}

			user := googlegithub.User{User: *i.GetUser()}
			convU, err := user.ToV1Mannequin(r.org)
			if err != nil {
				r.err = fmt.Errorf("error converting commit comment author to User: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: convU}}) {
				return
			}

			conv, err := i.ToV1CommitComment()
			if err != nil {
				r.err = fmt.Errorf("error converting to v1.CommitComment: %w", err)
				return
			}
			if !yield(&v1.Resource{Resource: &v1.Resource_CommitComment{CommitComment: conv}}) {
				return
			}

			if fetchErr.Err() != nil {
				return
			}
		}
	}
}

// commitCommentsIterBuilder returns a function that builds an iterator for fetching all commit comments on a repo using the given GitHub client.
func commitCommentsIterBuilder(ctx context.Context, c *github.Client, owner, repo string) func(fetchErr *FetchErr) iter.Seq[*ogithub.RepositoryComment] {
	return func(fetchErr *FetchErr) iter.Seq[*ogithub.RepositoryComment] {
		scanner := NewScanner[*ogithub.RepositoryComment](c, defaultPerPage)
		defer func() { fetchErr.setErr(scanner.Err()) }()
		return scanner.All(func(c *github.Client, listOptions ogithub.ListOptions) ([]*ogithub.RepositoryComment, *ogithub.Response, error) {
			rlCtx := context.WithValue(ctx, ogithub.SleepUntilPrimaryRateLimitResetWhenRateLimited, true)
			return c.CommitComments.ListComments(rlCtx, owner, repo, &listOptions)
		})
	}
}
