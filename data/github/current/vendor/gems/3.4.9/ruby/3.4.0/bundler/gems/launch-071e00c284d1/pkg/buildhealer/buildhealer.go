package buildhealer

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type HealReason uint

const (
	ReasonManual HealReason = iota
	ReasonScheduled
)

// Healer is designed to reconcile check suites and workflow build states with the status/conclusion handed in.
type Healer struct {
	obs           *observability.Observability
	gf            github.Factory
	ghTwirpClient ghtwirp.Client
	wfbRepo       deployer.WorkflowBuildsRepository
}

// New returns a new Healer
func New(obs *observability.Observability, gf github.Factory, ghTwirpClient ghtwirp.Client, wfbRepo deployer.WorkflowBuildsRepository) Healer {
	return Healer{obs, gf, ghTwirpClient, wfbRepo}
}

// CompleteBuild identifies the fix required and then applies it, returning the fix type, if the run was healed in dotcom, and an error.
func (h *Healer) CompleteBuild(ctx context.Context, w WorkflowInfo, status, conclusion string, reason HealReason) (string, bool, error) {
	// If the build is not completed, return an error as we should have sent a cancel request before getting
	// to here. Otherwise we need to learn what kind of statuses we might be seeing here to know how to build
	// fixers for them.
	if status != azptypes.StatusCompleted {
		return "", false, kvperrors.With("unexpected run info status in build healer", kvp.String("gh.launch.workflow_run.status", status))
	}

	var fixer checkSuiteFixer
	var dotcomState *github.CheckSuiteInfo
	var gc github.Client

	isDisabled, err := h.ghTwirpClient.IsRepositoryActionsDisabled(ctx, w.RepositoryID)
	if err != nil {
		h.obs.Debug(ctx, "Could not determine whether repository is disabled", kvp.Any("exception.message", err))
	}

	if isDisabled {
		// If a repository is disabled, we will skip over its build
		fixer = &repositoryDisabled{}
	} else {
		// Make a github client for this repo
		gc, err = h.gf.NewClientForRepositoryOwnerDatabaseID(ctx, w.RepositoryID, w.OwnerID)
		if err != nil {
			return "", false, errors.Wrap(err, "error creating github client for repository")
		}

		if w.CheckSuiteID == "" {
			// If we don't have a check suite, skip check suite lookup and fixer categorization.
			fixer = &checkSuiteMissing{}
		} else {
			// Load the current state from dotcom
			dotcomState, err = gc.GetCheckSuiteFromDotcom(ctx, w.CheckSuiteID)
			if err != nil {
				return "", false, errors.Wrap(err, "error loading check suite from dotcom")
			}

			if dotcomState == nil {
				fixer = &workflowRunDeleted{}
			} else {
				// Categorize the state of the check suite
				fixer = h.categorizeCheckSuiteState(dotcomState, conclusion, reason)
			}
		}
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.workflow_healing.fixer", fixer.String()), kvp.String("gh.check_run.status", status), kvp.String("gh.launch.run.conclusion", conclusion))
	ctx = ctxstash.WithFields(ctx, fixer.LoggingFields()...)

	// Apply the changes to dotcom - this is a noop for some fixers
	newState, healed, err := fixer.Fix(ctx, gc, w, dotcomState)
	if err != nil {
		return "", healed, errors.Wrap(err, "error fixing check suite")
	}

	// Update the state in workflow_builds to avoid reprocessing.
	// azp_completed_at is also updated with time.Now().UTC(), so healing workflows will not impact the Run completion delays SLO
	err = h.wfbRepo.Complete(ctx, time.Now().UTC(), time.Now().UTC(), w.ID, newState)
	if err != nil {
		return "", healed, errors.Wrap(err, "error updating workflow build")
	}
	return fixer.String(), healed, nil
}

// WorkflowInfo represents the data about a workflow needed to heal one of it's builds.
type WorkflowInfo deployer.DataForHealer

func (h *Healer) categorizeCheckSuiteState(cs *github.CheckSuiteInfo, conclusion string, reason HealReason) checkSuiteFixer {
	if cs.Status == string(github.CheckSuiteCompletedStatus) {
		return &checkSuiteAlreadyCompleted{conclusion}
	}

	if cs.NumCheckRuns == 0 {
		return &checkSuiteNoCheckRuns{
			conclusion: conclusion,
			reason:     reason,
		}
	}

	var incompleteRuns []string
	for _, run := range cs.CheckRuns {
		if run.Status != string(github.CheckRunCompletedStatus) {
			incompleteRuns = append(incompleteRuns, run.ID)
		}
	}

	if len(incompleteRuns) == 0 {
		return &checkSuiteAllRunsComplete{conclusion}
	}
	return &checkSuiteSomeRunsIncomplete{
		incompleteRunsCount: len(incompleteRuns),
		conclusion:          conclusion,
		reason:              reason,
	}
}
