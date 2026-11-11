package jobservice

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/google/uuid"
)

// Fun suffixes to use when branch name conflicts occur
var branchNameSuffixes = []string{
	"again",
	"another-one",
	"yet-again",
	"one-more-time",
	"please-work",
}

// GeneratePotentialBranchNames generates a set of unique branch names that, at
// the time of creation, don't exist. We generate multiple names in case the branch
// does come into existence between the generation of this list and the creation of
// the branch
func (s *Service) GeneratePotentialBranchNames(ctx context.Context, branchPrefix, branchNameSuffix string, repoID uint64) []string {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GeneratePotentialBranchNames")
	defer span.End()

	// Prepend the prefix if it's not already present
	baseName := branchNameSuffix
	if !strings.HasPrefix(branchNameSuffix, branchPrefix+"/") {
		baseName = fmt.Sprintf("%s/%s", branchPrefix, branchNameSuffix)
	}

	potentialNames := make([]string, len(branchNameSuffixes)+2)
	potentialNames[0] = baseName

	for i, suffix := range branchNameSuffixes {
		potentialNames[i+1] = fmt.Sprintf("%s-%s", baseName, suffix)
	}

	uid := uuid.New()
	potentialNames[len(potentialNames)-1] = fmt.Sprintf("%s-%s", baseName, uid)

	logger := s.obsv.LoggerWithTelemetry(ctx)
	branchesExist, err := s.spokes.CheckForExistingBranches(ctx, repoID, potentialNames)
	if err != nil {
		logger.WithError(err).Warn("failed to check if potential branch names exist, trying them all anyway")
		return potentialNames
	}

	if len(branchesExist) != len(potentialNames) {
		logger.WithError(err).Warn("existing branch check returned incorrect number of results.  This should be fixed")
		return potentialNames
	}

	branchesThatDontExist := []string{}
	for i, exists := range branchesExist {
		if exists {
			logger.WithError(err).Info(fmt.Sprintf("branch exists, ignoring: %s", potentialNames[i]))
			continue
		}

		branchesThatDontExist = append(branchesThatDontExist, potentialNames[i])
	}

	return branchesThatDontExist
}

// Committer is an interface for getting commit author information.
type Committer interface {
	Committer() *gg.CommitAuthor
}

// CreateEmptyCommit creates a new empty commit in the repository for the job using Spokes.
func (s *Service) CreateEmptyCommit(ctx context.Context, gh Committer, job *jobs.Job) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateEmptyCommit")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("debug.base_commit", job.BaseCommit)).Info("debugging empty commit creation")

	// TODO (colbylwilliams): Check Rules here?

	committer := gh.Committer()
	commitOID, err := s.spokes.CreateEmptyCommit(ctx, sweagentd.CreateEmptyCommitOpts{
		RepoID:         uint64(job.RepoID),
		BaseRef:        job.BaseCommit,
		CommitterName:  committer.GetName(),
		CommitterEmail: committer.GetEmail(),
	})
	if err != nil {
		return "", goerrors.Errorf("failed to create new empty commit: %w", err)
	}

	return commitOID, nil
}

// CreateBranch creates a new branch in the repository for the job using Spokes.
func (s *Service) CreateBranch(ctx context.Context, gh Committer, job *jobs.Job, commitOID string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateBranch")
	defer span.End()

	committer := gh.Committer()
	err := s.spokes.CreateBranch(ctx, sweagentd.CreateBranchOpts{
		RepoID:         uint64(job.RepoID),
		CommitOID:      commitOID,
		BranchName:     job.BranchName,
		CommitterName:  committer.GetName(),
		CommitterEmail: committer.GetEmail(),
	})
	if err != nil {
		return goerrors.Errorf("failed to create new branch: %w", err)
	}

	return nil
}
