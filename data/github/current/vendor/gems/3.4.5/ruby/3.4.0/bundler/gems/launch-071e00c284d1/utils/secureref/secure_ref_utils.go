package secureref

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/github/go-kvp"
	githubgo "github.com/google/go-github/v25/github"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
)

// Matches the suffix of a git describe - possible exploit if branch name suffix matches (https://github.com/github/c2c-actions/issues/4577)
var gitDescribeRefRegex = regexp.MustCompile(`-[0-9]+-g([0-9A-Fa-f]){5,40}\z`)

var msgInvalidBaseRef = "Base ref can't be a commit sha"
var msgInvalidBaseRefPR = "Base ref can't be a pull request ref"
var msgInvalidBaseRefGitDescribe = "Base ref suffix can't match a git describe suffix"

// ErrInvalidBaseRefSha means the pull request target event was using a base ref that matched the base SHA
// This is not allowed as the SHA could be from a fork
var ErrInvalidBaseRefSha = errors.New(msgInvalidBaseRef)

// ErrInvalidBaseRefPR means the pull request target event was using a pull request ref as the base ref
// so it cannot be trusted
var ErrInvalidBaseRefPR = errors.New(msgInvalidBaseRefPR)

// ErrInvalidBaseRefGitDescribe means the pull request target event was using a base ref whose suffix matches the
// suffix of a git describe, which may be ambiguous with a short sha and cannot be trusted (https://github.com/github/c2c-actions/issues/4577)
var ErrInvalidBaseRefGitDescribe = errors.New(msgInvalidBaseRefGitDescribe)

// GetFullyQualifiedSecureRef returns a fully qualified secure ref is the input ref is valid branch (not a SHA, not a pull request ref, matching the suffix of a Git describe)
// An example input ref would be "main", and an example the fully qualified ref is "refs/heads/main"
func GetFullyQualifiedSecureRef(ctx context.Context, logger logger.Logger, baseBranch *githubgo.PullRequestBranch, eventName string) (types.GitRef, error) {
	baseRef := baseBranch.GetRef()
	baseSHA := baseBranch.GetSHA()

	// Since base ref could be a SHA from a fork, don't allow PR target events to use SHAs as their base ref
	// A short SHA is at least 4 characters, so allow short refs that happen to match the commit SHA like "b"
	if len(baseRef) > 3 && strings.HasPrefix(baseSHA, baseRef) {
		logger.Error(ctx, msgInvalidBaseRef, kvp.String("gh.launch.invalid_base_ref", baseRef), kvp.String("gh.launch.event.name", eventName))

		return types.GitRefZeroValue, ErrInvalidBaseRefSha
	}

	// A pull request ref could be a forked PR and can't be trusted
	if strings.HasPrefix(baseRef, "refs/pull/") {
		logger.Error(ctx, msgInvalidBaseRefPR, kvp.String("gh.launch.invalid_base_ref", baseRef), kvp.String("gh.launch.event.name", eventName))

		return types.GitRefZeroValue, ErrInvalidBaseRefPR
	}

	// Check if baseRef suffix matches the suffix of a git describe - possible exploit if branch name suffix matches. Git describe suffix (https://github.com/github/c2c-actions/issues/4577)
	match := gitDescribeRefRegex.MatchString(baseRef)
	if match {
		logger.Error(ctx, msgInvalidBaseRefGitDescribe, kvp.String("gh.launch.invalid_base_ref", baseRef), kvp.String("gh.launch.event.name", eventName))

		return types.GitRefZeroValue, ErrInvalidBaseRefGitDescribe
	}

	// Get fully qualified base commit sha and ref - possible exploit if branch name is a short sha, so
	// add /refs/heads/ to prevent that exploit (https://github.com/github/c2c-actions/issues/3148)
	fqRef := types.GitRef(baseRef)
	if !fqRef.IsHeadRef() {
		fqRef = types.NewBranchRef(baseRef)
	}

	return fqRef, nil
}
