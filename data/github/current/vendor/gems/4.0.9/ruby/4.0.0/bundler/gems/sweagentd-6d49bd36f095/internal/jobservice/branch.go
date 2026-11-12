package jobservice

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/google/uuid"
)

// ErrBaseRefNotFound is returned when the base ref for a branch cannot be resolved.
var ErrBaseRefNotFound = errors.New("base ref not found")

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

// CreateEmptyCommit creates a new empty commit in the repository for the job using Spokes.
func (s *Service) CreateEmptyCommit(ctx context.Context, gh github.Committer, job *jobs.Job) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateEmptyCommit")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("debug.base_commit", job.BaseCommit)).Info("debugging empty commit creation")

	// TODO (colbylwilliams): Check Rules here?

	committer := gh.Committer()
	opts := sweagentd.CreateEmptyCommitOpts{
		RepoID:         uint64(job.RepoID),
		BaseRef:        job.BaseCommit,
		AuthorName:     committer.GetName(),
		AuthorEmail:    committer.GetEmail(),
		CommitterName:  committer.GetName(),
		CommitterEmail: committer.GetEmail(),
	}

	// Wire up commit signing when the Twirp client is available so the
	// initial empty commit is signed.
	if s.twirp != nil {
		// When signing, the committer must be GitHub's web-flow identity so the
		// system GPG key matches during signature verification. The author
		// remains the bot identity.
		if s.committerName != "" {
			opts.CommitterName = s.committerName
		}
		if s.committerEmail != "" {
			opts.CommitterEmail = s.committerEmail
		}

		api := s.twirp.SweagentdAPI()
		opts.SignCommit = func(ctx context.Context, payload string) (string, error) {
			resp, err := api.SignCommit(ctx, &sweagentdv1.SignCommitRequest{
				RepositoryId:      uint64(job.RepoID),
				Payload:           payload,
				AgentId:           job.AgentID,
				AttributionUserId: uint64(job.ActorID),
			})
			if err != nil {
				return "", err
			}
			return resp.Signature, nil
		}
	}

	commitOID, err := s.spokes.CreateEmptyCommit(ctx, opts)
	if err != nil {
		if errors.Is(err, spokes.ErrRefNotFound) {
			return "", goerrors.Errorf("%w: %w", ErrBaseRefNotFound, err)
		}
		return "", goerrors.Errorf("failed to create new empty commit: %w", err)
	}

	return commitOID, nil
}

// ResolveBaseRef resolves the job's base commit ref to a commit SHA without creating a commit.
// This is used for task-mode branches where no empty "Initial plan" commit is needed.
func (s *Service) ResolveBaseRef(ctx context.Context, job *jobs.Job) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.ResolveBaseRef")
	defer span.End()

	oid, err := s.spokes.GetObjectIDForRef(ctx, uint64(job.RepoID), job.BaseCommit)
	if err != nil {
		if errors.Is(err, spokes.ErrRefNotFound) {
			return "", goerrors.Errorf("%w: %w", ErrBaseRefNotFound, err)
		}
		return "", goerrors.Errorf("failed to resolve base ref: %w", err)
	}

	return oid, nil
}

// CreateBranch creates a new branch in the repository for the job using Spokes.
func (s *Service) CreateBranch(ctx context.Context, gh github.Committer, job *jobs.Job, commitOID string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateBranch")
	defer span.End()

	committer := gh.Committer()
	opts := sweagentd.CreateBranchOpts{
		RepoID:         uint64(job.RepoID),
		CommitOID:      commitOID,
		BranchName:     job.BranchName,
		CommitterName:  committer.GetName(),
		CommitterEmail: committer.GetEmail(),
	}

	if s.committerName != "" {
		opts.CommitterName = s.committerName
	}
	if s.committerEmail != "" {
		opts.CommitterEmail = s.committerEmail
	}
	err := s.spokes.CreateBranch(ctx, opts)
	if err != nil {
		return goerrors.Errorf("failed to create new branch: %w", err)
	}

	return nil
}
