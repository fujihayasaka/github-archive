package servermigrator

import (
	"fmt"
	"iter"

	"github.com/github/migrations-vnext/internal/pkg/github"
	ogithub "github.com/google/go-github/v65/github"
)

// getterFunc is the function called by Scanner to gather resources from
// the GitHub API. This must be used in conjunction with the Scanner. The
// ListOptions passed into the function must be used by the client.
type getterFunc[T any] func(*github.Client, ogithub.ListOptions) ([]T, *ogithub.Response, error)

// Scanner is a generic type that handles pagination and interruption
// for gathering resources from the GitHub API.
type Scanner[T any] struct {
	client  *github.Client
	perPage int
	err     error
}

// NewScanner creates and returns an instance of Scanner.
func NewScanner[T any](c *github.Client, perPage int) *Scanner[T] {
	return &Scanner[T]{
		client:  c,
		perPage: perPage,
	}
}

// All uses an iterator to gather all the T resources from the GitHub API.
func (s *Scanner[T]) All(f getterFunc[T]) iter.Seq[T] {
	return func(yield func(T) bool) {
		listOptions := ogithub.ListOptions{PerPage: s.perPage}
		for {
			resources, resp, err := f(s.client, listOptions)
			if err != nil {
				s.err = fmt.Errorf("error while scanning for resources: %w", err)
				return
			}
			for _, r := range resources {
				if !yield(r) {
					return
				}
			}
			if resp.NextPage == 0 {
				return
			}
			listOptions.Page = resp.NextPage
		}
	}
}

// Err returns the error that occurred while scanning for resources, if any.
func (s *Scanner[T]) Err() error {
	return s.err
}
