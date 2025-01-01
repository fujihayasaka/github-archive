// see docs/filtering.md
package azp

import (
	"context"
	"fmt"
	"strings"

	githubgo "github.com/google/go-github/v25/github"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-kvp"

	"github.com/github/launch/model"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowparser"
)

// Captures
type eventFiltering struct {
	event                  flowevents.GitHubEvent
	eventName              string
	workflowIdentifier     string
	action                 string
	branchOrTagRefAffected types.GitRef
	repoGID                string
	shouldRun              map[string]workflowFilteringResult
	pullID                 string

	headBase types.BeforeAfterSHA
}

type filterTypeName string

var (
	workflowsFilterName filterTypeName = "workflows"
	refsFilterName      filterTypeName = "refs"
	typesFilterName     filterTypeName = "types"
	pathsFilterName     filterTypeName = "paths"
)

type workflowFilteringResult struct {
	shouldRun  bool
	filterType filterTypeName
	reason     string
}

// see: https://github.com/github/github/blob/01589ca3855554943bd1c5ca8a5de04cab0ff2c7/lib/platform/models/actions_filter_diff.rb#L13-L15
const EmptyAdvisory = "empty"

type WorkflowFilterer interface {
	GetWorkflowFilter(context.Context, *workflowparser.ParsedWorkflows, string, flowevents.GitHubEvent, github.Client) (workflowbuild.WorkflowFilter, error)
}

type workflowFilterer struct {
	obs                   *observability.Observability
	repoOrOwnersFFChecker func(ctx context.Context, featureFlag string, repositoryID types.GlobalID) bool
}

func NewWorkflowFilterer(obs *observability.Observability, repoOrOwnersFFChecker func(ctx context.Context, featureFlag string, repositoryID types.GlobalID) bool) WorkflowFilterer {
	return workflowFilterer{
		obs:                   obs,
		repoOrOwnersFFChecker: repoOrOwnersFFChecker,
	}
}

func (p workflowFilterer) GetWorkflowFilter(ctx context.Context, workflows *workflowparser.ParsedWorkflows, eventName string, event flowevents.GitHubEvent, ghClient github.Client) (workflowbuild.WorkflowFilter, error) {
	ctx, span := tracing.StartWithOpFuncName(ctx, "WorkflowFiltering")
	defer span.End()

	ef := &eventFiltering{
		event:     event,
		eventName: eventName,
		shouldRun: map[string]workflowFilteringResult{},
	}

	if !anyWorkflowHasEvent(workflows, eventName) {
		p.obs.Log(ctx, "filter generation done, no workflows for event")
		return ef, nil
	}

	p.prepareFilter(event, ef)
	span.SetAttributes(
		attribute.String("gh.repo.global_id", ef.repoGID),
		attribute.String("gh.launch.event.name", eventName),
	)

	p.obs.Log(ctx, "event filter",
		kvp.String("gh.launch.event.name", eventName),
		kvp.String("gh.launch.event.type", ef.action),
		kvp.String("gh.pull_request.global_id", ef.pullID),
		kvp.String("gh.launch.affected_ref.branch_or_tag", ef.branchOrTagRefAffected.String()),
		kvp.String("gh.launch.head.base.before_sha", ef.headBase.Before.String()),
		kvp.String("gh.launch.head.base.after_sha", ef.headBase.After.String()),
	)

	// set baseline: whether the workflow is interested in the event
	for workflowFileReference, pl := range workflows.PathToWorkflow {
		_, ok := pl.OnForEvent(ef.eventName)
		ef.shouldRun[workflowFileReference.Path] = workflowFilteringResult{shouldRun: ok}
	}

	if !ef.branchOrTagRefAffected.IsZeroValue() {
		err := p.andFilter(ctx, runRefGlobs, refsFilterName, workflows, ef)
		if err != nil {
			return nil, err
		}
	}

	if len(ef.workflowIdentifier) > 0 {
		err := p.andFilter(ctx, workflowIdentifierFilters, workflowsFilterName, workflows, ef)
		if err != nil {
			return nil, err
		}
	}

	err := p.andFilter(ctx, runTypeFilters, typesFilterName, workflows, ef)
	if err != nil {
		return nil, err
	}

	if !ef.headBase.IsZeroValue() && !ef.branchOrTagRefAffected.IsTagRef() {
		err := p.andPathFilter(ctx, workflows, ef, ghClient)
		if err != nil {
			return nil, err
		}
	}

	// workflows which are filtered in will have "workflow_filter.type" and
	// "workflow_filter.reason" corresponding to the last filter which was passed
	for wfPath, wfFilterResult := range ef.shouldRun {
		if wfFilterResult.shouldRun {
			p.obs.Log(ctx, "workflow filtered in",
				kvp.String("gh.launch.workflow.file_path", wfPath),
				kvp.String("gh.launch.workflow_filter.type", string(wfFilterResult.filterType)),
				kvp.String("gh.launch.workflow_filter.reason", wfFilterResult.reason),
			)
		}
	}

	return ef, nil
}

func (p workflowFilterer) prepareFilter(event flowevents.GitHubEvent, ef *eventFiltering) {
	// Set the event action if one is present.
	ef.action = flowevents.ExtractEventAction(event)

	// Set the event workflow if one is present.
	if eventWithWorkflow, ok := event.(flowevents.ActionableWorkflow); ok {
		if workflow := eventWithWorkflow.GetWorkflow(); workflow != nil {
			ef.workflowIdentifier = strings.ToLower(workflow.Name)
		}
	}

	if push, ok := event.(*githubgo.PushEvent); ok {
		ef.branchOrTagRefAffected = types.GitRef(push.GetRef())
		ef.headBase = types.BeforeAfterSHAFromStrings(push.GetBefore(), push.GetAfter())
		ef.repoGID = push.GetRepo().GetNodeID()
	} else if pre, ok := event.(*githubgo.PullRequestEvent); ok {
		pr := pre.GetPullRequest()
		ef.headBase = types.BeforeAfterSHAFromStrings(pr.GetBase().GetSHA(), pr.GetHead().GetSHA())
		// normalise to match push's full ref format
		ef.branchOrTagRefAffected = types.NewBranchRef(pr.GetBase().GetRef())
		ef.repoGID = pre.GetRepo().GetNodeID()
		ef.pullID = pre.PullRequest.GetNodeID()
	} else if wr, ok := event.(*githubgo.WorkflowRunEvent); ok {
		if wr.WorkflowRun.HeadBranch != nil {
			ef.branchOrTagRefAffected = types.NewBranchRef(wr.WorkflowRun.GetHeadBranch())
		}
		ef.repoGID = wr.GetRepository().GetNodeID()
	} else if mge, ok := event.(*githubgo.MergeGroupEvent); ok {
		mg := mge.GetMergeGroup()
		ef.branchOrTagRefAffected = types.GitRef(mg.GetBaseRef())
		ef.repoGID = mge.GetRepo().GetNodeID()
	}
}

func (p workflowFilterer) andPathFilter(ctx context.Context, workflows *workflowparser.ParsedWorkflows, ef *eventFiltering, ghClient github.Client) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	pathsToSpecs := make(map[string]*workflowparser.GlobFilterSpec)
	for workflowFileReference, wf := range workflows.PathToWorkflow {
		if !ef.willRun(workflowFileReference.Path) {
			continue
		}
		ps := wf.PathFilters(ef.eventName)
		if ps != nil {
			pathsToSpecs[workflowFileReference.Path] = ps
		}
	}
	if len(pathsToSpecs) == 0 {
		return nil
	}

	res, err := ghClient.GetFilterDiff(ctx, types.NewGlobalID(ctx, ef.repoGID), ef.headBase, ef.branchOrTagRefAffected, types.NewGlobalID(ctx, ef.pullID))
	if err != nil {
		return err
	}

	if len(res.Paths) == 0 {
		p.obs.Log(ctx, "filter diff result contained no paths",
			kvp.String("gh.launch.head.base.before_sha", ef.headBase.Before.String()),
			kvp.String("gh.launch.head.base.after_sha", ef.headBase.After.String()),
			kvp.String("gh.launch.event.ref", ef.branchOrTagRefAffected.String()),
			kvp.String("gh.launch.advisory_value", res.Advisory),
		)
	}

	applyToAll := func(run bool, reason string) {
		for path := range pathsToSpecs {
			p.applyFilterResult(ctx, ef, path, pathsFilterName, run, reason)
		}
	}

	// GetFilterDiff returns "empty" for empty diffs. We handle this
	// case uniquely if actions_treat_empty_advisories_as_passed
	// FF is enabled
	ffEnabled := map[string]bool{
		github.TreatEmptyAdvisoriesAsPassed:       false,
		github.PathsIgnoreEmptyPushBypassesParser: false,
	}
	if res.Advisory != "" {
		run, reason, exitEarly := p.handleAdvisory(ctx, res.Advisory, ef)

		if exitEarly {
			applyToAll(run, "advisory: "+reason)
			return nil
		}

		ffEnabled[github.TreatEmptyAdvisoriesAsPassed] = true
		ffEnabled[github.PathsIgnoreEmptyPushBypassesParser] = p.repoOrOwnersFFChecker(ctx, github.PathsIgnoreEmptyPushBypassesParser, types.NewGlobalID(ctx, ef.repoGID))
	}

	// run each path filter vs the diff generated
	for path, spec := range pathsToSpecs {
		reason := ""
		if len(spec.Sequence) == 0 {
			// no globs will always result in a pass
			reason = "no globs"
		} else if len(res.Paths) == 0 {
			// no paths always result in a fail as long as there are globs
			// AND actions_paths_ignore_empty_push_bypasses_parser is disabled
			reason = "empty diff"
		}

		if ffEnabled[github.TreatEmptyAdvisoriesAsPassed] && len(res.Paths) == 0 && ef.eventName == flowevents.Push && !spec.IsInclude {
			p.obs.Debug(ctx, "would bypass parser globbing if FF enabled",
				kvp.String("gh.launch.workflow.file_path", path),
				kvp.String("gh.launch.filter.type", string(pathsFilterName)),
				kvp.String("gh.launch.filter.reason", reason),
				kvp.Int("gh.launch.filter.diff_paths.count", len(res.Paths)),
				kvp.String("gh.launch.filter.spec", fmt.Sprintf("IsInclude: %t, Globs: %s", spec.IsInclude, strings.Join(spec.Sequence, "|"))),
				kvp.String("gh.launch.head.base.before_sha", ef.headBase.Before.String()),
				kvp.String("gh.launch.head.base.after_sha", ef.headBase.After.String()),
				kvp.String("gh.launch.event.ref", ef.branchOrTagRefAffected.String()),
			)

			if ffEnabled[github.PathsIgnoreEmptyPushBypassesParser] {
				passed := true
				reason = "empty diff on 'push' event with paths-ignore filters"
				p.logPathFilterResult(ctx, fmt.Sprintf("bypassing parser globbing since %s FF enabled: path filter result", github.PathsIgnoreEmptyPushBypassesParser), path, reason, passed, spec, ef, res.Paths)
				p.applyFilterResult(ctx, ef, path, pathsFilterName, passed, reason)
				continue
			}
		}

		passed, err := workflowparser.MatchGlobs(spec, res.Paths)
		if err != nil {
			// some errors, e.g timeouts, are treated as a pass
			passed, err = p.handleGlobError(ctx, err)
			if err != nil {
				if berr, ok := err.(workflowparser.BadGlobError); ok {
					// Globbing errors are wrapped as user errors to avoid reporting them.
					return terrors.NewUserError(fmt.Sprintf("Encountered an issue parsing path(s) \"%s\" in a workflow.", berr.Error()))
				}
				return err
			}
			reason = "handled glob error"
		}
		p.applyFilterResult(ctx, ef, path, pathsFilterName, passed, reason)
	}

	return nil
}

func (p workflowFilterer) handleAdvisory(ctx context.Context, reason string, ef *eventFiltering) (bool, string, bool) {
	passed := true
	exitAfterHandling := true
	if reason == EmptyAdvisory {
		passed = false
		if ef.eventName == flowevents.Push && p.repoOrOwnersFFChecker(ctx, github.TreatEmptyAdvisoriesAsPassed, types.NewGlobalID(ctx, ef.repoGID)) {
			passed = true
			exitAfterHandling = false
		}
	}
	reason = strings.TrimPrefix(reason, "unavailable:")
	if len(reason) == 0 {
		reason = "unknown"
	}
	p.obs.Log(ctx, "could not generate diff for path filter",
		kvp.Bool("gh.launch.filter.passed", passed), kvp.String("gh.launch.filter.reason", reason))
	p.obs.Counter(ctx, metrickeys.WorkflowDiffAdvisory, map[string]string{
		"reason": reason,
	}, 1)
	return passed, reason, exitAfterHandling
}

func (p workflowFilterer) logPathFilterResult(ctx context.Context, msg string, wfPath string, filterReason string, filterPassed bool, filterSpec *workflowparser.GlobFilterSpec, eventFilter *eventFiltering, paths []string) {
	p.obs.Log(ctx, msg,
		kvp.String("gh.launch.workflow.file_path", wfPath),
		kvp.Bool("gh.launch.filter.passed", filterPassed),
		kvp.String("gh.launch.filter.type", string(pathsFilterName)),
		kvp.String("gh.launch.filter.reason", filterReason),
		kvp.Int("gh.launch.filter.diff_paths.count", len(paths)),
		kvp.String("gh.launch.filter.spec", fmt.Sprintf("IsInclude: %t, Globs: %s", filterSpec.IsInclude, strings.Join(filterSpec.Sequence, "|"))),
		kvp.String("gh.launch.head.base.before_sha", eventFilter.headBase.Before.String()),
		kvp.String("gh.launch.head.base.after_sha", eventFilter.headBase.After.String()),
		kvp.String("gh.launch.event.ref", eventFilter.branchOrTagRefAffected.String()),
	)
}

func (p workflowFilterer) handleGlobError(ctx context.Context, err error) (bool, error) {
	if globText, ok := workflowparser.WasSingleGlobTimeout(err); ok {
		p.obs.Error(ctx, "single glob runtime exceeded", kvp.String("gh.launch.glob.value", globText))
		p.obs.Counter(ctx, metrickeys.SingleGlobTimeout, nil, 1)
		return true, nil
	}
	if workflowparser.IsTotalDiffRuntime(err) {
		p.obs.Error(ctx, "aggregate glob runtime exceeded")
		p.obs.Counter(ctx, metrickeys.AggregateDiffGlobTimeout, nil, 1)
		return true, nil
	}
	return false, err
}

func (p workflowFilterer) applyFilterResult(ctx context.Context, ef *eventFiltering, workflowPath string, filterName filterTypeName, passed bool, reason string) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.Bool("gh.launch.workflow_filter.passed", passed),
		attribute.String("gh.launch.workflow_filter.type", string(pathsFilterName)),
		attribute.String("gh.launch.workflow_filter.reason", reason),
		attribute.String("gh.launch.workflow.file_path", workflowPath),
	))
	defer span.End()

	if passed {
		if wfFilterResult, ok := ef.shouldRun[workflowPath]; ok {
			wfFilterResult.filterType = filterName
			wfFilterResult.reason = reason

			ef.shouldRun[workflowPath] = wfFilterResult
		}
		return
	}

	ef.shouldRun[workflowPath] = workflowFilteringResult{
		shouldRun:  false,
		filterType: filterName,
		reason:     reason,
	}
	p.obs.Log(ctx, "workflow filtered out",
		kvp.String("gh.launch.workflow.file_path", workflowPath),
		kvp.String("gh.launch.workflow_filter.type", string(filterName)),
		kvp.String("gh.launch.workflow_filter.reason", reason),
	)
}

type workflowFilterFn func(ctx context.Context, trig workflowparser.EventConfig, ef *eventFiltering, path string) (bool, string, error)

func (p workflowFilterer) andFilter(ctx context.Context, filter workflowFilterFn, filterType filterTypeName, workflows *workflowparser.ParsedWorkflows, ef *eventFiltering) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	for workflowFileReference, pl := range workflows.PathToWorkflow {
		// if we have already filtered out a workflow, we're done (AND)
		if !ef.willRun(workflowFileReference.Path) {
			continue
		}
		trig, _ := pl.OnForEvent(ef.eventName)
		ok, reason, err := filter(ctx, trig, ef, workflowFileReference.Path)
		if err != nil {
			return err
		}
		p.applyFilterResult(ctx, ef, workflowFileReference.Path, filterType, ok, reason)
	}
	return nil
}

func workflowIdentifierFilters(_ context.Context, trig workflowparser.EventConfig, ef *eventFiltering, path string) (bool, string, error) {
	workflowsFilter := trig.Workflows
	ok, err := workflowparser.MatchGlobs(&workflowparser.GlobFilterSpec{
		Sequence:  workflowsFilter.LowerCaseValue(),
		IsInclude: true,
	}, []string{ef.workflowIdentifier})
	if err != nil {
		if berr, ok := err.(workflowparser.BadGlobError); ok {
			// Globbing errors are wrapped as user errors to avoid reporting them.
			return false, "bad glob error with workflow identifier filters", terrors.NewUserError(fmt.Sprintf("Encountered an issue parsing workflow trigger(s) \"%s\" in a workflow \"%s\".", berr.Error(), path))
		}
		return false, "other error with workflow identifier filters", err
	}
	return ok, "", nil
}

func runTypeFilters(_ context.Context, trig workflowparser.EventConfig, ef *eventFiltering, path string) (bool, string, error) {
	// first check if the sub-type of this event is filtered out as a whole
	typeFilters := trig.Types
	if !typeFilters.HasGlobs() {
		typeFilters = flowevents.GetEventTypeGlobs(ef.eventName)
	}
	ok, err := workflowparser.MatchGlobs(&workflowparser.GlobFilterSpec{
		Sequence:  typeFilters.Value(),
		IsInclude: true,
	}, []string{ef.action})
	if err != nil {
		if berr, ok := err.(workflowparser.BadGlobError); ok {
			// Globbing errors are wrapped as user errors to avoid reporting them.
			return false, "bad glob error with type filters", terrors.NewUserError(fmt.Sprintf("Encountered an issue parsing event type(s) \"%s\" in a workflow \"%s\".", berr.Error(), path))
		}
		return false, "other error with type filters", err
	}
	return ok, "", nil
}

func runRefGlobs(_ context.Context, trig workflowparser.EventConfig, ef *eventFiltering, path string) (bool, string, error) {
	ref := ef.branchOrTagRefAffected
	filter := trig.BranchFilters()
	if ref.IsTagRef() {
		filter = trig.TagFilters()
	}
	refsAreBeingFiltered := trig.BranchFilters() != nil || trig.TagFilters() != nil
	if !refsAreBeingFiltered {
		return true, "refs are not being filtered", nil
	}
	if filter == nil {
		// we support two types of ref filters. If only one is present, filter out events affecting the other type of ref
		return false, "ref filter is nil", nil
	}
	ok, err := workflowparser.MatchGlobs(filter, []string{ref.TagOrHeadName()})
	if err != nil {
		if berr, ok := err.(workflowparser.BadGlobError); ok {
			// Globbing errors are wrapped as user errors to avoid reporting them.
			return false, "bad glob error with refs filter", terrors.NewUserError(fmt.Sprintf("Encountered an issue parsing ref(s) \"%s\" in a workflow \"%s\".", berr.Error(), path))
		}
		return false, "other error with refs filter", err
	}

	// for workflow_run events, ensure that the matching ref is associated
	// with the original repository and not a fork IFF the user is making
	// use of the 'branches' filter.
	// for context, see: https://github.com/github/security/issues/6363
	if ok {
		if wr, o := ef.event.(*githubgo.WorkflowRunEvent); o && trig.Branches.IsPresent() {
			if wr.GetWorkflowRun() == nil || wr.GetWorkflowRun().GetRepository().GetID() == 0 || wr.GetWorkflowRun().GetHeadRepository().GetID() == 0 {
				return false, "parts of WorkflowRun.* properties were unexpectedly nil so cannot evaluate", nil
			}
			if wr.GetWorkflowRun().GetRepository().GetID() != wr.GetWorkflowRun().GetHeadRepository().GetID() {
				return false, "matching ref is associated with workflow_run event originating from a fork", nil
			}
		}
	}

	return ok, "", nil
}

func (ef *eventFiltering) ShouldRun(_ context.Context, wf model.Workflow) bool {
	return ef.shouldRun[wf.Path].shouldRun
}

func (ef *eventFiltering) willRun(p string) bool {
	return ef.shouldRun[p].shouldRun
}

func anyWorkflowHasEvent(workflows *workflowparser.ParsedWorkflows, eventType string) bool {
	if eventType == flowevents.Dynamic {
		// All workflows match the dynamic event
		return true
	}

	for _, wf := range workflows.PathToWorkflow {
		if _, ok := wf.OnForEvent(eventType); ok {
			return true
		}
	}
	return false
}
