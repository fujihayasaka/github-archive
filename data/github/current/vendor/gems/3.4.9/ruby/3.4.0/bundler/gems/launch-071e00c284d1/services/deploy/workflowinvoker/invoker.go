package workflowinvoker

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	githubgo "github.com/google/go-github/v25/github"
	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/ghtwirp"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/flow/flowfile"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/deploy/workflowinvoker/ctxkeys"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/clock"
	"github.com/github/launch/utils/secureref"
)

// Invoker takes an Invocation object, requests the WorkflowInvocationData from GitHub and processes it with a WorkflowInvoker

type Invoker interface {
	// Start begins 0 or more flows.
	Start(
		ctx context.Context,
		obs *observability.Observability,
		inv Invocation,
		isFinalAttempt bool,
		labeler customerlabels.CustomerLabeler,
	) error
}

func NewInvoker(workflowInvokerFactory WorkflowInvokerFactory, ghClientFactory ghclient.Factory, ghTwirpClient ghtwirp.Client, repo deployer.WorkflowBuildsRepository, workflowStartErrHandlerFactory WorkflowStartErrHandlerFactory, isLabEnvironment, isEnterprise bool, reporter *slometrics.Reporter, runServiceClient runservice.Client, resultsClient results.Client) Invoker {
	env := launchconfig.ProductionAppEnv
	if isLabEnvironment {
		env = launchconfig.LabAppEnv
	}
	return &invoker{
		errorHandlerFactory:    workflowStartErrHandlerFactory,
		workflowInvokerFactory: workflowInvokerFactory,
		ghClientFactory:        ghClientFactory,
		ghTwirpClient:          ghTwirpClient,
		repo:                   repo,
		env:                    env,
		clock:                  clock.New(),
		backoffTimer:           nil, // use backoff's default timer
		isEnterprise:           isEnterprise,
		reporter:               reporter,
		runServiceClient:       runServiceClient,
		resultsClient:          resultsClient,
	}
}

type invoker struct {
	errorHandlerFactory    WorkflowStartErrHandlerFactory
	workflowInvokerFactory WorkflowInvokerFactory
	ghClientFactory        ghclient.Factory
	ghTwirpClient          ghtwirp.Client
	repo                   deployer.WorkflowBuildsRepository
	env                    launchconfig.AppEnv
	clock                  clock.Clock
	backoffTimer           backoff.Timer
	isEnterprise           bool
	reporter               *slometrics.Reporter
	runServiceClient       runservice.Client
	resultsClient          results.Client
}

//gocyclo:ignore
func (i *invoker) Start(ctx context.Context, o *observability.Observability, inv Invocation, isFinalAttempt bool, labeler customerlabels.CustomerLabeler) error {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.event.name", inv.Event.Name),
	))
	ctx = context.WithValue(ctx, ctxkeys.ExecutingActorIDContextKey, inv.ExecutingActor.ID)
	ctx = context.WithValue(ctx, ctxkeys.RepoIDContextKey, inv.Target.RepositoryID)
	if inv.ExistingCheckSuite != nil {
		span.SetAttributes(attribute.Bool("gh.launch.rerun", true))
	}
	defer func() {
		if rmd := mw.GetRequestMetadata(ctx); rmd != nil {
			span.SetAttributes(attribute.String("gh.launch.invocation_status", rmd.StatTags()["status"]))
		}
		span.End()
	}()

	ctx, obs := NewObservability(ctx, o, inv)

	// To be removed as part of https://github.com/github/actions-relaunch/issues/84
	timer := obs.LegacyTimer()           //nolint:staticcheck
	defer timer.End(ctx, invokedStatKey) //nolint:staticcheck

	now := time.Now()
	defer func() { obs.Timing(ctx, invokedStatKey, statter.Tags{}, time.Since(now)) }()

	addEventOriginTimeCheckpoint(inv, obs)
	logInvokerStartStage(ctx, obs)
	defer func() { obs.logCompletion(ctx) }()

	// make it easier to search for specific logs
	if prEvent, ok := inv.Event.Ghe.(flowevents.HasPullRequest); ok {
		ctx = ctxstash.WithFields(ctx, kvp.Int("gh.pull_request.number", prEvent.GetPullRequest().GetNumber()))
	}
	if issueEvent, ok := inv.Event.Ghe.(flowevents.HasIssue); ok {
		ctx = ctxstash.WithFields(ctx, kvp.Int("gh.launch.issue.number", issueEvent.GetIssue().GetNumber()))
	}
	if changeEvent, ok := inv.Event.Ghe.(flowevents.HasBeforeAndAfter); ok {
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.before_sha", changeEvent.GetBefore()))
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.after_sha", changeEvent.GetAfter()))
	}

	if !i.isEnterprise {
		isSpammy, err := i.ghTwirpClient.IsUserSpammy(ctx, inv.ExecutingActor.ID)
		if err != nil {
			obs.Report(ctx, errors.Wrap(err, "error checking if executing user is spammy"))
		}
		if isSpammy {
			obs.Log(ctx, "executing actor is spammy", kvp.String("gh.launch.executing_actor.global_id", string(inv.ExecutingActor.ID)))
		}
		// neither the executing nor the triggering actors should be spammy
		if !isSpammy && !inv.TriggeringActor.ID.IsEquivalent(inv.ExecutingActor.ID) {
			isSpammy, err = i.ghTwirpClient.IsUserSpammy(ctx, inv.TriggeringActor.ID)
			if err != nil {
				obs.Report(ctx, errors.Wrap(err, "error checking if triggering user is spammy"))
			}
			if isSpammy {
				obs.Log(ctx, "triggering actor is spammy", kvp.String("gh.launch.triggering_actor.id", string(inv.TriggeringActor.ID)))
			}
		}

		if isSpammy {
			obs.Log(ctx, "skipping workflow run for spammy or suspended user")
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "spammy"})
			return nil
		}

		isDisabled, err := i.ghTwirpClient.IsRepositoryActionsDisabled(ctx, inv.Target.RepositoryID)
		if err != nil {
			obs.Report(ctx, errors.Wrap(err, "error checking if repository actions disabled"))
		}

		if isDisabled {
			obs.Log(ctx, "skipping build for repository because of missing GitHub client")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "twirp_repo_actions_disabled",
			})

			return nil
		}
	}

	msg := slometrics.NewQueueRunMessage(
		ctx, &obs.Observability,
		slometrics.ActorID(inv.TriggeringActor.ID), "", slometrics.RepositoryID(inv.Target.RepositoryID), inv.Event.Name, inv.Event.Action,
		slometrics.WithRerunInfo(inv.RerunInfo))

	var (
		client       ghclient.Client
		err          error
		functionName string
	)

	if inv.Target.RepositoryOwnerDatabaseID != 0 {
		client, err = i.ghClientFactory.NewClientForRepositoryOwnerDatabaseID(ctx, inv.Target.RepositoryID, inv.Target.RepositoryOwnerDatabaseID)
		functionName = "NewClientForRepositoryOwnerDatabaseID"
	} else {
		var ownerID types.GlobalID
		// TODO: This should be != types.NilGlobalID https://github.com/github/actions-launch/issues/395
		if inv.Target.RepositoryOwnerGlobalID == types.NilGlobalID {
			ownerID = inv.Target.RepositoryOwnerGlobalID
		}

		client, err = i.ghClientFactory.NewClientForRepositoryOwner(ctx, inv.Target.RepositoryID, ownerID)
		functionName = "NewClientForRepositoryOwner"
	}

	if err != nil {
		// This can't be createErrorCheckSuite'ed because there wouldn't be a
		// client to report with!
		obs.Error(ctx, "unable to set up GitHub client", kvp.Err(err))
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"status":       "unhandled_error",
			"error_type":   functionName,
			"error_reason": "internal",
			// Used for SLO calculation.
			"event_triggers_run": guessIfEventTriggersRun(inv.Event).String(),
		})

		if isFinalAttempt && guessIfEventTriggersRun(inv.Event) != eventTriggersRunUnlikely {
			i.reporter.ReportQueueRunError(ctx, o, msg, functionName)
		}
		return terrors.WrapAsRetryable(tracing.RecordError(span, err), "error returned for new client")
	}

	data, err := i.getInvocationData(ctx, obs, client, inv, i.env)
	if err != nil {
		span.RecordError(err)
		errorReason := "internal"

		if errors.Is(err, ErrMergeableCommitTimeout) {
			// We do see merge commit timeouts for few repos due to a known issue https://github.com/github/pull-requests/issues/3106
			// skipping reporting error for these repos inorder to decrease noise for Queue Run Availability SLO
			if !i.isEnterprise && isFinalAttempt {
				noisyRepos := map[int64]struct{}{
					6223686:   {}, // Canva/canva
					46020406:  {}, // instacart/carrot
					15539164:  {}, // databricks/universe
					855930129: {}, // databricks-eng/universe
				}

				_, found := noisyRepos[inv.Target.RepositoryDatabaseID]

				if found {
					obs.Debug(ctx, "skipping build for PR for repositories with very frequent pushes to target branch")
					mw.TagStatsWith(ctx, reqmeta.Tags{
						"status":      "skipped",
						"skip_reason": "repo_with_very_frequent_commits_to_target_branch",
					})
					return nil
				}
			}
			errorReason = "merge_commit_timeout"
		}

		if terrors.IsRateLimitError(err) {
			errorReason = "rate_limit_error"
		}

		if errors.Is(err, ErrPullRequestClosedWithoutMerging) {
			// Known issue. See https://github.com/github/c2c-actions-experience/issues/5332.
			obs.Debug(ctx, "skipping build for PR closed without being merged. test merge commit not available")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "pr_closed_without_merging",
			})
			return nil
		}

		if errors.Is(err, ErrOldPullRequestCommit) {
			obs.Debug(ctx, "skipping build for old pull_request commit. test merge commit not available")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "old_pull_request_commit",
			})
			return nil
		}

		if errors.Is(err, ErrMergeConflicts) {
			obs.Debug(ctx, "skipping build for pull_request event. PR has merge conflicts")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "merge_conflicts",
			})
			return nil
		}

		if errors.Is(err, secureref.ErrInvalidBaseRefSha) {
			obs.Debug(ctx, "skipping build for pull_request_target event, base ref can't be a commit sha")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "invalid_base_ref",
			})
			return nil
		}

		if errors.Is(err, secureref.ErrInvalidBaseRefPR) {
			obs.Debug(ctx, "skipping build for pull_request_target event, base ref can't be a pull request ref")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "invalid_base_ref_pr",
			})
			return nil
		}

		if errors.Is(err, secureref.ErrInvalidBaseRefGitDescribe) {
			obs.Debug(ctx, "skipping build for pull_request_target event, base ref suffix can't be a git describe suffix")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "invalid_base_ref_git_describe",
			})
			return nil
		}

		if errors.Is(err, ghclient.WorkflowsCommitNotFound) {
			errorReason = "workflows_commit_not_found"
		}

		if _, ok := errors.Cause(err).(*terrors.NotFoundError); ok {
			// graphql NOT_FOUND errors are returned for spammy and non-existent actors
			errorReason = "graphql_not_found"

			obs.Debug(ctx, "received not found from graphQL, checking if repository is spammy")
			if isDisabled := i.isSpammyWorkflowRunForRepositoryOrPullRequest(ctx, &inv, obs); isDisabled {
				return nil
			}
		}

		if terrors.IsRefResolutionError(err) {
			errorReason = "failed_ref_resolution"
		}

		// This shouldn't be createErrorCheckSuite'ed because it's most likely
		// a race between activity on github and an action invocation. In
		// this case, we also don't know if this is even an event that
		// the user cares about.
		// Because this is likely to be a user error, log it but don't
		// report to the user or to haystack.
		obs.Error(ctx, "unable to get data for workflow", kvp.Err(err))
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"status":       "unhandled_error",
			"error_type":   "getGitHubData",
			"error_reason": errorReason,
			// Used for SLO calculation.
			"event_triggers_run": guessIfEventTriggersRun(inv.Event).String(),
		})

		// N.B. There is a chance (*invoker).Start will be called again even if it returns a permanent error.
		if (!terrors.IsRetryable(err) || isFinalAttempt) && guessIfEventTriggersRun(inv.Event) != eventTriggersRunUnlikely {
			i.reporter.ReportQueueRunError(ctx, o, msg, errorReason)
		}
		return err
	}

	ctx = ctxstash.WithTags(ctx, stats.Tags{"customer_label": labeler.LabelFor(data.NWO.Owner, data.PlanOwner.Name)})

	if i.shouldSkipCI(ctx, obs, inv, data) {
		obs.Debug(ctx, "skipping build for repository because commit message has 'skip' annotation")
		mw.TagStatsWith(ctx, reqmeta.Tags{
			"status":      "skipped",
			"skip_reason": "commit_message_has_skip_annotation",
		})
		return nil
	}

	ctx = ctxstash.WithFields(ctx, kvp.Bool("gh.repo.public", !data.RepoIsPrivate))
	errorHandler := i.errorHandlerFactory.Build(
		obs,
		inv,
		client,
		i.ghTwirpClient,
		i.resultsClient,
		i.isEnterprise,
		data.WorkflowFeatureFlags.SkipParserErrorsEnabled,
	)

	workflowInvoker := i.workflowInvokerFactory.Build(obs, inv, client, i.ghTwirpClient, errorHandler, i.runServiceClient, i.resultsClient)
	if startErrs := workflowInvoker.Start(ctx, data, isFinalAttempt); startErrs != nil && len(startErrs.Errors()) > 0 {
		for _, startErr := range startErrs.Errors() {
			// If the invocation should create check suites for errors (meaning it's the
			// final attempt of a retryable error) or the error itself is not retryable,
			// create a check suite.
			if isFinalAttempt || !startErr.retryable {
				errorHandler.CreateErrorCheckSuite(ctx, startErr)
			}
		}

		// CreateErrorCheckSuite already called ReportQueueRunError if appropriate.
		return startErrs
	}

	return nil
}

// get what we need to make a decision on workflow execution
func (i *invoker) getInvocationData(ctx context.Context, obs *Observability, client ghclient.Client, inv Invocation, env launchconfig.AppEnv) (*types.WorkflowInvocationData, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	eventCommitSHA, eventCommitRef, err := i.resolveCommitAndRef(ctx, obs, client, inv)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// checkout commit might be different than the event commit, ex: on: pull_request and re-run
	checkoutCommitSHA, checkoutCommitRef, err := i.resolveCheckoutCommitAndRef(ctx, obs, client, inv, eventCommitSHA, eventCommitRef)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// Use workflow file from checkout commit instead of event commit
	data, err := client.GetDataForWorkflowInvocation(ctx, inv.Target.RepositoryID, checkoutCommitSHA, inv.ExecutingActor.ID, flowfile.PipelineDirectoryForEnvironment(env))
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// set both the EventCommit and CheckoutCommit to use same Event Commit by default
	data.References.EventCommit = types.NewWorkflowInvocationReference(eventCommitSHA, eventCommitRef)
	data.References.CheckoutCommit = types.NewWorkflowInvocationReference(checkoutCommitSHA, checkoutCommitRef)
	// only check branch protection for head ref since there is no branch protection for refs/tags/* or refs/pull/*
	if checkoutCommitRef.IsHeadRef() {
		// checkout ref is protected or not.
		checkoutRefProtected, err := client.IsRefProtected(ctx, inv.Target.RepositoryID, checkoutCommitRef)
		if err != nil {
			// set ref_protected to false if we fail to check branch protection. (the branch might got deleted)
			checkoutRefProtected = false
			obs.Error(ctx, err.Error())
		}

		// set whether the checkout ref is protected or not
		data.References.CheckoutRefProtected = checkoutRefProtected
	} else {

		// set CheckoutRefProtected to false when we don't query server
		data.References.CheckoutRefProtected = false
	}

	return data, nil
}

func (i *invoker) resolveCheckoutCommitAndRef(ctx context.Context, obs *Observability, client ghclient.Client, inv Invocation, eventCommitSHA types.CommitSha, eventCommitRef types.GitRef) (types.CommitSha, types.GitRef, error) {
	// For re-run set checkout commit same as the previous run.
	if inv.ExistingCheckSuite != nil {
		return inv.ExistingCheckSuite.CheckoutSHA, inv.ExistingCheckSuite.CheckoutRef, nil
	}

	// pull requests
	if prEvent, ok := inv.Event.Ghe.(flowevents.HasPullRequest); ok {
		if inv.Event.Name == flowevents.PullRequestTarget {
			// on: pull_request_target will use workflow file
			// and checkout code from base branch instead of the head branch.
			baseBranch := prEvent.GetPullRequest().GetBase()

			fqRef, err := secureref.GetFullyQualifiedSecureRef(ctx, obs.Logger, baseBranch, inv.Event.Name)
			if err != nil {
				return types.CommitShaZeroValue, types.GitRefZeroValue, err
			}

			// Let's resolve the base ref to ensure we always get the head of base ref
			// This ensures that we always pull the latest version of the workflow from that base ref when we run
			// ...instead of pulling the version from the SHA that represents the base even if that ref has moved on
			// ...Checkout https://github.com/github/github/issues/121622 and https://github.com/github/c2c-actions/issues/2395, we shouldn't switch this back to reading from event
			fqBaseCommitSha, fqBaseHeadRef, err := client.ResolveRef(ctx, inv.Target.RepositoryID, fqRef)
			if err != nil {
				obs.Error(ctx, "The fully qualified ref could not be found in the base branch")
				return types.CommitShaZeroValue, types.GitRefZeroValue, err
			}
			return fqBaseCommitSha, fqBaseHeadRef, nil
		}

		// on: pull_request will want to run when a mergeable
		// merge commit (or test merge commit) is present.
		return i.resolveMergeCommitAndRef(ctx, obs, inv, client, prEvent, eventCommitSHA)
	}

	// all other cases use the event commit/ref
	return eventCommitSHA, eventCommitRef, nil
}

func (i *invoker) resolveCommitAndRef(ctx context.Context, obs *Observability, client ghclient.Client, inv Invocation) (types.CommitSha, types.GitRef, error) {
	event := inv.Event
	target := inv.Target

	if event.Commit.IsZeroValue() && event.Ref.IsZeroValue() {
		// No commit sha and no ref
		return types.CommitShaZeroValue, types.GitRefZeroValue, errors.New("unable to resolve with nothing to go on")
	}

	if event.Ref == types.DefaultBranch {
		// Resolve a default branch ref
		return client.ResolveDefaultBranch(ctx, target.RepositoryID)
	}

	if event.Commit.IsZeroValue() {
		return client.ResolveRef(ctx, target.RepositoryID, event.Ref)
	}

	if event.Ref.IsZeroValue() {
		// Pass commit sha through for unknown git reference
		return event.Commit, types.GitRefZeroValue, nil
	}

	if event.Ref.IsHeadRef() || event.Ref.IsTagRef() {
		// Head/tag refs should be passed through
		return event.Commit, event.Ref, nil
	}

	if event.Name == flowevents.Dynamic {
		// A dynamic workflow has already resolved a ref and event commit
		// Since that commit SHA is used to create the workflow run & check suite,
		// it needs to be used for the workflow invocation as well.
		// See https://github.com/github/code-scanning/issues/15255
		return event.Commit, event.Ref, nil
	}

	// Resolve other unresolved refs
	sha, ref, err := client.ResolveRef(ctx, target.RepositoryID, event.Ref)
	if err != nil {
		if inv.ExistingCheckSuite != nil {
			// in case the ref is not valid (ex. release tag is deleted before rerun)
			// we cannot resolve sha from ref but in this case still commit should be valid
			obs.Log(ctx, "Event ref could not be resolved, using event commit instead for rerun")
			return event.Commit, types.GitRefZeroValue, nil
		}

		return types.CommitShaZeroValue, types.GitRefZeroValue, err
	}

	return sha, ref, nil
}

// resolveMergeCommitAndRef polls for that merge commit and return an error of one is never
// created, or we encounter some other error.
func (i *invoker) resolveMergeCommitAndRef(ctx context.Context, obs *Observability, inv Invocation, client ghclient.Client, prEvent flowevents.HasPullRequest, eventCommitSHA types.CommitSha) (types.CommitSha, types.GitRef, error) {
	pullRequest := prEvent.GetPullRequest()
	isMergeable := pullRequest.GetMergeable()
	mergeCommitSha := types.CommitSha(pullRequest.GetMergeCommitSHA())

	getPullRequestGitRef := func(pr *githubgo.PullRequest, merged bool) types.GitRef {
		if merged {
			baseRef := pr.GetBase().GetRef()
			fqRef := types.GitRef(baseRef)
			if !fqRef.IsHeadRef() {
				fqRef = types.NewBranchRef(baseRef)
			}
			return fqRef
		}

		ref := fmt.Sprintf("refs/pull/%d/merge", pr.GetNumber())
		return types.GitRef(ref)
	}

	// There may be one immediately available in the event payload.
	if isMergeable && mergeCommitSha != "" {
		obs.Debug(ctx,
			"merge commit for PR ready",
			kvp.String("gh.launch.merge_commit.sha", mergeCommitSha.String()),
		)

		return mergeCommitSha, getPullRequestGitRef(pullRequest, pullRequest.GetMerged()), nil
	} // Wait for a mergeable merge commit.

	obs.Debug(ctx, "searching for the merge commit")

	latestStartTime := time.Now()
	mergeCommitSha, mergeState, err := i.awaitMergeableCommit(ctx, obs, inv, client, prEvent, eventCommitSHA)
	if err != nil {
		return types.CommitShaZeroValue, types.GitRefZeroValue, err
	}
	resolvedAt := time.Now()

	// record the resolution time so it's logged later when a run is queued
	obs.AddCheckpoint(observability.PRMergeCommitResolvedAtCheckpoint, resolvedAt)

	fields := []kvp.Field{
		kvp.String("gh.launch.merge_commit.sha", mergeCommitSha.String()),
		kvp.Int("gh.launch.latest_poll_time_ms", int(time.Since(latestStartTime)/time.Millisecond)),
	}

	// Get the original receive time for the aqueduct job we're processing, in leiu of the time for the first call to awaitMergeableCommit.
	// The aqueduct job may have been rescheduled to continue polling for a merge commit.
	origRecvAt, ok, err := obs.GetCheckpointTime(observability.AqOrigJobRecvAtCheckpoint)
	if err != nil {
		return types.CommitShaZeroValue, types.GitRefZeroValue, errors.Wrap(err, "could not retrieve aqueduct job's original received_at time")
	}
	if ok {
		// If the p99 times for merge commit resolution are too high, we may want to:
		// - Reschedule the aqueduct job to run more frequently following ErrMergeableCommitTimeout
		// - Check for CreatePullRequestMergeCommitJob execution delays
		obs.Timing(ctx, "delays.orig_job_recv_at.pr_merge_commit_resolved_at", statter.Tags{}, resolvedAt.Sub(origRecvAt))
		fields = append(fields,
			kvp.Time("gh.aqueduct.job.received_at", origRecvAt),
			kvp.Duration("gh.launch.merge_commit_resolution_time_sec", resolvedAt.Sub(origRecvAt)),
		)
	}

	obs.Debug(ctx, "merge commit for PR resolved", fields...)

	return mergeCommitSha, getPullRequestGitRef(pullRequest, mergeState.Merged), nil
}

func (i *invoker) isSpammyWorkflowRunForRepositoryOrPullRequest(ctx context.Context, inv *Invocation, obs *Observability) bool {
	// Only check for disabled actions in production
	if !i.isEnterprise {
		// Check and make sure that repository isn't disabled again.
		isRepoDisabled, err := i.ghTwirpClient.IsRepositoryActionsDisabled(ctx, inv.Target.RepositoryID)
		if err != nil {
			obs.Error(ctx, errors.Wrap(err, "error checking if repository is disabled").Error())
		}

		if isRepoDisabled {
			obs.Debug(ctx, "skipping build for repository because repository or owner is spammy")
			mw.TagStatsWith(ctx, reqmeta.Tags{
				"status":      "skipped",
				"skip_reason": "twirp_repo_actions_disabled",
			})
			return isRepoDisabled
		}

		// In production, check and make sure that if we have a pull request event, that the
		// creator of it is not a bad actor
		if prEvent, ok := inv.Event.Ghe.(flowevents.HasPullRequest); ok {
			obs.Debug(ctx, "checking if pull request creator is spammy")
			creatorNodeID := prEvent.GetPullRequest().GetUser().GetNodeID()
			isCreatorSpammy, err := i.ghTwirpClient.IsUserSpammy(ctx, types.NewGlobalID(ctx, creatorNodeID))
			if err != nil {
				obs.Report(ctx, errors.Wrap(err, "error checking if pull request owner is spammy"))
			}

			if isCreatorSpammy {
				obs.Debug(ctx, "skipping build for repository because pull request creator is spammy")
				mw.TagStatsWith(ctx, reqmeta.Tags{
					"status":      "skipped",
					"skip_reason": "spammy_pr_user",
				})
				return isCreatorSpammy
			}
		}
	}

	return false
}

func (i *invoker) awaitMergeableCommit(ctx context.Context, obs *Observability, inv Invocation, client ghclient.Client, e flowevents.HasPullRequest, eventCommitSHA types.CommitSha) (types.CommitSha, *ghclient.PullRequestMergeState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGID := inv.Target.RepositoryID
	prNumber := e.GetPullRequest().GetNumber()

	bo := backoff.NewExponentialBackOff()
	bo.InitialInterval = 500 * time.Millisecond
	bo.MaxInterval = 1500 * time.Millisecond
	bo.MaxElapsedTime = 5 * time.Second
	bo.Clock = i.clock
	ticker := backoff.NewTickerWithTimer(bo, i.backoffTimer)

	attempts := 0
	closedAndNotMergedCount := 0
	for range ticker.C {
		attempts++

		mergeState, err := client.GetMergeStatusForPullRequest(ctx, repoGID, prNumber)
		if err != nil {
			obs.Counter(ctx, "merge_commit_errors", nil, 1)
			obs.Error(ctx, "error getting merge commit for pull request", kvp.Bool("gh.launch.resolved", false), kvp.Err(err))
			ticker.Stop()
			return types.CommitShaZeroValue, nil, tracing.RecordError(span, err)
		}

		if mergeState.Merged {
			// For now we're not going to check merge commit parents for merged PRs.
			// PRs that are squashed or rebased result in a merge commit with one parent.
			if mergeState.HasMergeCommit() {
				obs.Debug(ctx, "resolved merge commit for pull request", kvp.Bool("gh.launch.resolved", true), kvp.Int("gh.launch.attempts", attempts))
				ticker.Stop()
				return mergeState.MergeCommit, mergeState, nil
			}
		} else {
			if mergeState.Mergeable == githubv4.MergeableStateConflicting {
				obs.Debug(ctx, "pull request has merge conflicts", kvp.Bool("gh.launch.resolved", false), kvp.Int("gh.launch.attempts", attempts))
				ticker.Stop()
				return types.CommitShaZeroValue, nil, tracing.RecordError(span, ErrMergeConflicts)
			}

			if mergeState.HasMergeCommitForEventCommit(eventCommitSHA) {
				obs.Debug(ctx, "resolved merge commit for pull request", kvp.Bool("gh.launch.resolved", true), kvp.Int("gh.launch.attempts", attempts))
				ticker.Stop()
				return mergeState.MergeCommit, mergeState, nil
			}

			// N.B. mergeState.PRHeadCommit is zero when the head branch was deleted, or Launch doesn't have access to the head repo for a private fork PR.
			if !mergeState.PRHeadCommit.IsZeroValue() && !mergeState.PRHeadCommit.IsEqual(eventCommitSHA) {
				obs.Error(ctx, "pull_request event commit is old, doesn't match PR head ref", kvp.Bool("gh.launch.resolved", false), kvp.Int("gh.launch.attempts", attempts))
				ticker.Stop()
				return types.CommitShaZeroValue, nil, tracing.RecordError(span, ErrOldPullRequestCommit)
			}

			if !mergeState.MergeCommit.IsZeroValue() {
				obs.Debug(ctx, "ignoring merge commit with wrong parent", kvp.Int("gh.launch.attempts", attempts))
			}

			if mergeState.Closed {
				closedAndNotMergedCount++
			}
		}
	}

	// After our polling times out, check if the responses consistently indicated the PR is closed but not merged.
	// We continue polling because Splunk shows there are occasionally delays in the graphQL API reflecting:
	// 1. A previously closed PR has been re-opened. If we stopped polling that could impact the processing of `pull_request:reopened` webhooks.
	// 2. A closed PR is merged as well, and has a merge commit. See https://github.com/github/coding/issues/2856.
	if closedAndNotMergedCount == attempts {
		obs.Error(ctx, "pull request closed without merging, test merge commits will not be produced", kvp.Bool("gh.launch.resolved", false), kvp.Int("gh.launch.attempts", attempts))
		ticker.Stop()
		return types.CommitShaZeroValue, nil, tracing.RecordError(span, ErrPullRequestClosedWithoutMerging)
	}

	obs.Error(ctx, "timeout getting merge commit for pull request", kvp.Bool("gh.launch.resolved", false), kvp.Int("gh.launch.attempts", attempts))
	return types.CommitShaZeroValue, nil, tracing.RecordError(span, ErrMergeableCommitTimeout)
}

const (
	trueStr  = "true"
	falseStr = "false"
)

func (i *invoker) shouldSkipCI(ctx context.Context, obs *Observability, inv Invocation, data *types.WorkflowInvocationData) bool {
	tags := statter.Tags{}
	defer obs.Counter(ctx, "should_skip_ci_check_count", tags, 1)

	if !isSkippablePushOrPullRequest(inv) {
		tags["is_skippable_event"] = falseStr
		return false
	}
	tags["is_skippable_event"] = trueStr

	var commitMessage types.CommitMessage
	switch {
	case !inv.Event.CommitMessage.IsZeroValue():
		tags["needs_get_commit_message_rpc"] = falseStr
		commitMessage = inv.Event.CommitMessage
	default:
		tags["needs_get_commit_message_rpc"] = trueStr
		var err error
		commitMessage, err = i.getCommitMessage(ctx, inv, data.References.EventCommit.CommitSHA)
		if err != nil {
			tags["get_commit_message_rpc"] = "error"
			// log but schedule the build in any case
			obs.Report(ctx, errors.Wrap(err, "error getting commit message for workflow"),
				kvp.String("gh.launch.commit_sha", string(data.References.EventCommit.CommitSHA)),
			)
			return false
		}
		tags["get_commit_message_rpc"] = "success"
	}

	shouldSkipCI := hasSkipRunAnnotation(commitMessage)
	tags["has_skip_ci_annotation"] = strconv.FormatBool(shouldSkipCI)

	return shouldSkipCI
}

func (i *invoker) getCommitMessage(ctx context.Context, inv Invocation, sha types.CommitSha) (types.CommitMessage, error) {
	_, repoID, err := inv.Target.RepositoryID.Decode()
	if err != nil {
		return types.CommitMessageZeroValue, errors.Wrap(err, "decoding repository ID")
	}

	msg, err := i.ghTwirpClient.GetCommitMessage(ctx, repoID, sha)
	if err != nil {
		return types.CommitMessageZeroValue, errors.Wrap(err, "requesting commit message from dotcom")
	}
	return msg, nil
}
