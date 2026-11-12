package jobservice

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

type PullRequestCreator interface {
	CreatePullRequest(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
}

func (s *Service) OpenPullRequest(ctx context.Context, gh PullRequestCreator, assignment *jobs.Assignment, job *jobs.Job, title, body string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.OpenPullRequest")
	defer span.End()

	req := &sweagentdTwirp.CreatePullRequestRequest{
		RepositoryId:      uint64(job.RepoID),
		PrName:            title,
		PrDescription:     body,
		HeadBranchName:    job.BranchName,
		BaseBranchName:    job.BaseCommit,
		Draft:             true,
		AttributionUserId: uint64(job.ActorID),
		SessionId:         job.SessionID,
	}

	pr, err := gh.CreatePullRequest(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if !errors.As(err, &twirpErr) || twirpErr.Code() != twirp.AlreadyExists {
			return fmt.Errorf("failed to create pull request: %w", err)
		}
	}

	id := int64(pr.PullRequest.Id)
	number := int(pr.PullRequest.GithubNumber)

	assignment.PullRequestID = id
	assignment.PullRequestNumber = number

	job.PullRequestID = id
	job.PullRequestNumber = number

	s.updateRequestContextJob(ctx, job)

	requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		ID:     &id,
		Number: number,
	})

	return nil
}
