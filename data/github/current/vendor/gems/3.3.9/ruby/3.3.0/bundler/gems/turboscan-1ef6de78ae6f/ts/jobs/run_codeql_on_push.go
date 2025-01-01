package jobs

import (
	"context"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/managedanalyses"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

type RunCodeqlOnPush struct {
	RepoID          ts.RepositoryEID
	OwnerID         ts.OwnerEID
	Ref             ts.Ref
	Sha             ts.Sha
	ActorGRID       ts.ActorGRID
	ActorLogin      string
	InDefaultBranch bool
	EventTimeStamp  *sqltime.Time
}

func (r RunCodeqlOnPush) GetRepositoryID() *ts.RepositoryEID {
	return &r.RepoID
}

var _ aqueduct.EnqueableJob = (*RunCodeqlOnPush)(nil)

func (r RunCodeqlOnPush) Name() string {
	return "RunCodeqlOnPush"
}

func (r RunCodeqlOnPush) Queue() string {
	return "turboscan-run-codeql-on-push"
}

func (r RunCodeqlOnPush) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (r RunCodeqlOnPush) actor() *ts.ActorGRIDLogin {
	return &ts.ActorGRIDLogin{
		GRID:  r.ActorGRID,
		Login: r.ActorLogin,
	}
}

func (r RunCodeqlOnPush) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	ctx = appctx.WithKVPs(ctx, r.Sha, r.Ref)
	if s == nil || s.ManagedAnalyses == nil {
		return errors.New("missing required services")
	}

	// Forcing the FF for the entire job because we do not have the owner information everywhere
	if flipper.HasCodeScanningActionsYml(ctx, r.OwnerID, r.RepoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningActionsYml)
	}
	if flipper.HasCodeScanningPrivateRegistry(ctx, r.OwnerID, r.RepoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningPrivateRegistry)
	}

	return r.perform(ctx, s.ManagedAnalyses)
}

func (r RunCodeqlOnPush) perform(ctx context.Context, ma *maservice.ManagedAnalyses) error {
	if ma.LaunchApiClient == nil {
		appctx.Logger(ctx).Error("Actions is not configured.")
		return nil
	}

	exists, err := ma.DataService.PreviousRunExists(ctx, r.RepoID, r.Sha)
	if err != nil {
		return errors.Wrap(err, "failed to check if previous run exists")
	}
	if exists {
		appctx.Logger(ctx).Info("Codeql workflow already triggered, codeql_run records found in db")
		return nil
	}

	// get a current config, will it return any staged config at this point?
	config, _, codeqlPacks, err := ma.RequireRunnableCodeqlConfig(ctx, r.RepoID)
	if err != nil {
		switch {
		case errors.Is(err, ts.ErrCodeqlRepoNotFound):
			appctx.Logger(ctx).Info("Managed analyses disabled for repository")
			return nil
		case errors.Is(err, ts.ErrNotOnboarded):
			appctx.Logger(ctx).Info("Managed analyses is not enabled for this repository")
			return nil
		case errors.Is(err, maservice.ErrRequiredServicesNotEnabled):
			appctx.Logger(ctx).Info("Required services are not enabled")
			return nil
		case errors.Is(err, ts.ErrMissingActionsInstallationID):
			appctx.Logger(ctx).Info("Missing Actions Installation ID")
			return nil
		default:
			return err
		}
	}

	// holds a steady or validation run, depending on config changes
	var run *ts.CodeqlRun

	if r.InDefaultBranch && shallTriggerJITValidation(ctx, r.RepoID, ma, config.TemplateVersion) {
		validationRun, newConfig, err := r.setUpJitValidation(ctx, ma, config, codeqlPacks)
		// we swallow any errors to allow fallback to a steady run for the current config
		if err == nil {
			run = validationRun
			config = newConfig
		}
	}

	// if at this point we haven't already created a jit run, then we need to create a steady run
	if run == nil {
		run, err = config.NewRun(r.actor(), r.Ref, r.Sha, ts.CodeqlRunTriggeringEvent_PUSH, r.InDefaultBranch, r.OwnerID, codeqlPacks, r.EventTimeStamp)
		// update here to submit value to db
		if err != nil {
			return errors.Wrap(err, "failed to build new run")
		}
	}

	err = ma.LaunchApiClient.RunDynamicWorkflow(ctx, run)
	if err != nil {
		appctx.Logger(ctx).Error("failed to submit dynamic workflow", kvp.String("gh.turboscan.error", err.Error()))
		if errors.Is(err, ts.ErrCouldNotResolveRef) {
			// no need to retry this failure, see https://github.com/github/code-scanning/issues/8571
			return nil
		}
		if errors.Is(err, ts.ErrSpammyUser) {
			// no need to retry this failure
			return nil
		}
		return errors.Wrap(err, "failed to submit dynamic workflow")
	}
	managedanalyses.DynamicWorkflowRunLogAndStats(ctx, config, run)

	err = ma.DataService.WithTransaction(func(tx managedanalyses.CodeqlDB) error {
		if run.JITValidation() {
			// If the run was a JIT run, we have created a new config that we need to update.
			err = tx.CreateStagedCodeqlConfig(ctx, run.Config)
			if err != nil {
				return errors.Wrap(err, "failed to enable managed analysis")
			}
		}

		err = ma.DataService.CreateCodeqlRun(ctx, run)
		if err != nil {
			return errors.Wrap(err, "failed to create an entry for ts_codeql_run after submitting dynamic workflow")
		}
		return nil
	})
	if err != nil {
		// We do not return this error since everything else should still work and we do not want to retry the job
		// and spend customer's Actions minutes on a rerun.
		appctx.Logger(ctx).Info("failed to create an entry for ts_codeql_run after submitting dynamic workflow", kvp.String("gh.turboscan.error", err.Error()))
		return nil
	}

	err = CancelObsoleteRuns(ctx, ma, run)
	if err != nil {
		// We do not return this error since everything else should still work and we do not want to retry the job
		// and spend customer's Actions minutes on a rerun.
		appctx.Logger(ctx).Info("failed to cancel workflow runs", kvp.String("gh.turboscan.error", err.Error()))
		return nil
	}

	return nil
}

const JIT_WAIT_BETWEEN_ATTEMPTS = time.Hour * 48
const JIT_MAX_NUMBER_OF_ATTEMPTS = 2

// shallTriggerJITValidation checks whether we should trigger
// a JIT validation run for the given repository and template version.
// It returns false if there is no need to upgrade, or if we already tried
// to upgrade too many times.
func shallTriggerJITValidation(ctx context.Context, repoID ts.RepositoryEID, ma *maservice.ManagedAnalyses, currentVersion string) bool {
	// If the template is up-to-date, we do not need to upgrade it.
	wt := ma.WorkflowsLibrary.GetWorkflowTemplate(ctx, repoID)
	if currentVersion == wt.Version {
		return false
	}

	ok, err := ma.DataService.CanAttemptJITValidation(ctx, repoID, wt.Version, JIT_MAX_NUMBER_OF_ATTEMPTS, JIT_WAIT_BETWEEN_ATTEMPTS)
	if err != nil {
		return false
	}

	if !ok {
		appctx.Logger(ctx).Info("JIT validation currently disallowed for this combination of repo and workflow template version",
			repoID.AsKVP(), wt.AsKVP(),
		)
		return false
	}

	return true
}

// setUpJitValidation creates a new staged config and associated validation run.
func (r RunCodeqlOnPush) setUpJitValidation(ctx context.Context, ma *maservice.ManagedAnalyses, config *ts.CodeqlConfig, codeqlPacks ts.CodeqlPacks) (*ts.CodeqlRun, *ts.CodeqlConfig, error) {
	// Create a new config.
	// All the configurable values should stay the same but:
	// 1. The Actor must be set to the bot.
	// 2. The template version must be updated.
	newConfig := config.CopyForUpdate()

	actor, err := ma.GetBotActor(ctx)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to get bot actor")
	}

	newConfig.OnboardedByActorGRID = actor.GRID
	newConfig.CreatedByActorLogin = actor.Login

	// create jit run with latest template
	wt := ma.WorkflowsLibrary.GetWorkflowTemplate(ctx, r.RepoID)
	run, err := newConfig.SetUpForValidationRun(r.Ref, r.Sha, wt, ts.CodeqlRunTriggeringEvent_PUSH, r.OwnerID, codeqlPacks)
	if err != nil {
		appctx.Logger(ctx).Info("failed to create JIT validation run", kvp.String("err", err.Error()))
		return nil, nil, err
	}

	return run, newConfig, nil
}
