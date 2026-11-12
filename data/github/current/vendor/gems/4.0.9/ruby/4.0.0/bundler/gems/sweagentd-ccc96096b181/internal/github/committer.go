package github

import gg "github.com/google/go-github/v75/github"

// Committer is an interface for types that can provide a git commit author.
type Committer interface {
	Committer() *gg.CommitAuthor
}

// Committer returns a CommitAuthor with the configured committer name and email.
func (ac *Client) Committer() *gg.CommitAuthor {
	return &gg.CommitAuthor{
		Name:  gg.Ptr(ac.app.CommitLogin()),
		Email: gg.Ptr(ac.app.CommitEmail()),
	}
}
