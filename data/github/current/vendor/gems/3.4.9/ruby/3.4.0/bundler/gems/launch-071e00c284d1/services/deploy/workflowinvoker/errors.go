// errors allow runners etc that pass errors back to invoker to provider
// specific types of errors, without creating a circular dep on invoker
package workflowinvoker

import (
	"time"

	"github.com/pkg/errors"

	terrors "github.com/github/launch/types/errors"
)

// ErrMergeableCommitTimeout is an error that occurs when a mergeable commit timeouts.
// We need retries to wait long enough for test merge commits to be produced. The
// Create Pull Request Merge Commit job can be significantly delayed for busy repos by
// its concurrency limits.
var ErrMergeableCommitTimeout = terrors.NewRetryableDuration("Could not resolve merge commit SHA for pull_request event within timeout", 10*time.Minute)

// ErrPullRequestClosedWithoutMerging means no further test merge commits will be produced.
// GitHub doesn't produce test merge commits for closed PRs; see https://github.com/github/c2c-actions-experience/issues/5332 and https://github.com/github/github/blob/56d58e2157ef3ccf0dc6ec3d3961bd3ae6ca4ee2/packages/pull_requests/app/models/pull_request.rb#L1203-L1206.
var ErrPullRequestClosedWithoutMerging = errors.New("Pull request closed without merging. Test merge commit will not be produced")

// ErrOldPullRequestCommit means there's been a more recent push to the PR head branch since the webhook event was produced.
// When the Create Pull Request Merge Commit (CPRMC) job runs it produces a merge commit for the current branch refs,
// so the test merge commit is unlikely to have the right parents for the event commit.
var ErrOldPullRequestCommit = errors.New("pull_request event commit is old, doesn't match PR head ref. Test merge commit will not be produced")

// ErrMergeConflicts means the pull request has merge conflicts that need to be resolved by the user.
var ErrMergeConflicts = errors.New("No merge commit available. Pull request has merge conflicts")
