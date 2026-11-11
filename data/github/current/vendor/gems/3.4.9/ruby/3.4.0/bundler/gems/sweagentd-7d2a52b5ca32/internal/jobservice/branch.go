package jobservice

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// BranchNameGenerator is an interface for generating unique branch names.
type BranchNameGenerator interface {
	EnsureUniqueBranchName(ctx context.Context, ownerLogin string, repoName string, branchName string) (string, error)
}

// GenerateBranchName generates a unique branch name for the job and sets the
// job's BranchName field.
func (s *Service) GenerateBranchName(ctx context.Context, gh BranchNameGenerator, job *jobs.Job, branchNameSuffix string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GenerateBranchName")
	defer span.End()

	newBranchName, err := gh.EnsureUniqueBranchName(ctx, job.RepoOwner, job.RepoName, branchNameSuffix)
	if err != nil {
		return fmt.Errorf("failed to generate branch name: %w", err)
	}

	job.BranchName = newBranchName

	s.updateRequestContextJob(ctx, job)

	return nil
}

// Committer is an interface for getting commit author information.
type Committer interface {
	Committer() *gg.CommitAuthor
}

// CreateBranch creates a new empty branch in the repository for the job using Spokes.
func (s *Service) CreateBranch(ctx context.Context, gh Committer, job *jobs.Job) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateBranch")
	defer span.End()

	// TODO (colbylwilliams): Check Rules here?

	committer := gh.Committer()
	_, err := s.spokes.CreateEmptyBranch(ctx, sweagentd.CreateEmptyBranchOpts{
		RepoID:         uint64(job.RepoID),
		BaseRef:        job.BaseCommit,
		BranchName:     job.BranchName,
		CommitterName:  committer.GetName(),
		CommitterEmail: committer.GetEmail(),
	})
	if err != nil {
		return fmt.Errorf("failed to create new empty branch: %w", err)
	}

	return nil
}
