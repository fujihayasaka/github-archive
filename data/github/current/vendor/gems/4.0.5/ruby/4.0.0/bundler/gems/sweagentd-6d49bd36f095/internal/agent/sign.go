package agent

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

// SignCommit signs a commit on behalf of the agent by calling the GitHub
// signing Twirp API. It constructs the Twirp request from the job context
// and the raw commit payload provided by the caller.
func (s *Service) SignCommit(ctx context.Context, job *jobs.Job, payload string) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "agent.Service.SignCommit")
	defer span.End()

	resp, err := s.ghtwirp.SweagentdAPI().SignCommit(ctx, &sweagentdv1.SignCommitRequest{
		RepositoryId:      uint64(job.RepoID),
		Payload:           payload,
		AgentId:           job.AgentID,
		AttributionUserId: uint64(job.ActorID),
	})
	if err != nil {
		return "", goerrors.Errorf("failed to sign commit: %w", err)
	}

	return resp.Signature, nil
}
