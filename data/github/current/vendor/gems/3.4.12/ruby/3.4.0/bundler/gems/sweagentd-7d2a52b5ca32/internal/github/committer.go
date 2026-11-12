package github

import gg "github.com/google/go-github/v75/github"

type Committer interface {
	Committer() *gg.CommitAuthor
}

// Committer returns a CommitAuthor with the configured committer name and email.
func (ac *Client) Committer() *gg.CommitAuthor {
	return &gg.CommitAuthor{
		Name:  &ac.githubCommitLogin,
		Email: &ac.githubCommitEmail,
	}
}
