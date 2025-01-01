package workflowparser

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"

	errs "github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
	"gopkg.in/yaml.v3"

	"github.com/github/go-kvp"

	"github.com/github/launch/model"
	launcherror "github.com/github/launch/types/errors"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/requiredworkflowutils"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	model2 "github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/types"
)

// keep unexported to avoid consumers coupling to the parsing struct, as its
// shape/typing has often changed to allow us to parse the YAML differently
type parseTarget struct {
	Name              string            `yaml:"name"`
	RunNameExpression yaml.Node         `yaml:"run-name"`
	On                workflowOnValue   `yaml:"on"`
	Jobs              jobMap            `yaml:"jobs"`
	Concurrency       *concurrencyValue `yaml:"concurrency"`
}

type concurrencyValue struct {
	Group string
}

const (
	maxWorkflowMebibytes       = 5
	mebibyte                   = 1024 * 1024
	workflowFileSizeMaxInBytes = maxWorkflowMebibytes * mebibyte
	// this comes from the size of our launch DB columns - e.g workflow_id and workflow_file_path
	// - the equivalent columns in ballast are 1024. MySQL utf8 varchar count characters not bytes.
	filePathMaxCodepoints = 255
	// how deep can workflows call into other workflows
	// with depth 1, a called workflow cannot call another reusable workflow
	MaxWorkflowCallDepth                = 3
	maxWorkflowFilesReferencedStandard  = 20  // Standard limit - how many workflows can be used in `jobs.uses` and further called workflow
	maxWorkflowFilesReferencedIncreased = 50  // Increased limit behind FF actions_max_workflow_files_increased - how many workflows can be used in `jobs.uses` and further called workflow
	workflowDispatchInputLimit          = 10  // Limit of input for `workflow_dispatch` event
	maxConcurrencyLength                = 400 // GroupName is defined as NVARCHAR(400) in tbl_GroupPermitQueue.sql in ADN.
	maxNameLength                       = 512 // Same as TimelineRecordNameMaxLength in actions-dotnet

	trimmedTextMarker = "..."
)

var (
	// call them megabytes in user-facing errors because it's the norm: https://tech.slashdot.org/story/01/12/23/1421225/megabytes-mb-or-mebibytes-mib
	errWorkflowFileTooLarge = errs.Errorf("Workflow files can be %d megabytes at largest", maxWorkflowMebibytes)
	errFilePathTooLong      = errs.Errorf("Workflow files paths can be at most %d unicode characters", filePathMaxCodepoints)
	// Depending on the source of the workflow file, it may have been truncated
	// before reaching our parser's size limit of `workflowFileSizeMaxInBytes`.
	// For the Spokes GetBlobContents API, this limit is 1 MB.
	// For the GraphQL blob API, this limit is 500 KB.
	errWorkflowFileTruncated = errs.Errorf("Workflow file too large")
)

type ParsedWorkflows struct {
	PathToWorkflow   map[types.WorkflowFileReference]Workflow
	InvalidWorkflows map[types.WorkflowFileReference]error
}

// Turns a pipeline set into the single model.Configuration which the code
// written for a single workflow file expects. We pull out actions  so they
// can be fed into validators and monitoring.
func (ps *ParsedWorkflows) Flow() *model.Configuration {
	c := &model.Configuration{
		Actions:   make([]*model.Action, 0),
		Workflows: make([]*model.Workflow, 0),
	}

	for _, w := range ps.PathToWorkflow {
		wc := WorkflowToConfiguration(&w)

		c.Workflows = append(c.Workflows, wc.Workflows...)
		c.Actions = append(c.Actions, wc.Actions...)
	}

	return c
}

// Find returns the workflow at the passed in path, ref, and SHA, or an error.
func (ps *ParsedWorkflows) Find(workflowReference types.WorkflowFileReference) (*Workflow, error) {
	w, ok := ps.PathToWorkflow[workflowReference]
	if !ok {
		return nil, errs.Errorf("workflow '%s' not found in parsed workflows with SHA: '%s' and Ref: '%s'", workflowReference.Path, workflowReference.SHA, workflowReference.Ref)
	}
	return &w, nil
}

func ParseWorkflows(ctx context.Context, files []types.ResolvedFile, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (*ParsedWorkflows, error) {
	ps := &ParsedWorkflows{
		PathToWorkflow:   make(map[types.WorkflowFileReference]Workflow),
		InvalidWorkflows: make(map[types.WorkflowFileReference]error),
	}

	var (
		wg   sync.WaitGroup
		psMu sync.Mutex
		done = make(chan struct{})
	)
	for _, f := range files {
		wg.Add(1)
		go func(f types.ResolvedFile) {
			defer wg.Done()
			c, err := Parse(ctx, f, featureFlags, workflowSource, runtimeHelper, actorID, obs)
			psMu.Lock()
			defer psMu.Unlock()

			if err == nil {
				ps.PathToWorkflow[c.FileReference] = *c
			} else {
				ps.InvalidWorkflows[fileReferenceFromFile(f)] = err
			}
		}(f)
	}
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-done:
		return ps, nil
	}
}

// Parse parses a workflow configuration and skips called workflows that are used inside it.
// Errors indicate semantically or syntactically invalid file.
func Parse(ctx context.Context, file types.ResolvedFile, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (*Workflow, error) {
	wf, _, _, err := parse(ctx, file, featureFlags, workflowSource, 0, false, runtimeHelper, actorID, obs)
	return wf, err
}

// This parses main workflow along with called workflows that are used inside it
// Errors indicate semantically or syntactically invalid file.
func ParseWithCalledWorkflows(ctx context.Context, file types.ResolvedFile, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (*Workflow, error) {
	wf, _, callDepth, err := parse(ctx, file, featureFlags, workflowSource, 0, true, runtimeHelper, actorID, obs)
	nestedCallTags := statter.Tags{
		"call_depth": strconv.Itoa(callDepth),
	}
	obs.Counter(ctx, metrickeys.NestedWorkflowsCallDepth, nestedCallTags, 1)
	return wf, err
}

func parse(ctx context.Context, file types.ResolvedFile, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, depth int, parseCalledWorkflows bool, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (*Workflow, int, int, error) {
	b := []byte(file.Text)
	filePath := file.Path

	if file.IsTruncated {
		return nil, 0, 0, errWorkflowFileTruncated
	}

	if len(b) > workflowFileSizeMaxInBytes {
		return nil, 0, 0, errWorkflowFileTooLarge
	}
	if utf8.RuneCountInString(filePath) > filePathMaxCodepoints {
		return nil, 0, 0, errFilePathTooLong
	}
	w := &Workflow{
		Path:          filePath,
		File:          file,
		FileReference: fileReferenceFromFile(file),
	}
	p := &w.parsed

	if err := yaml.Unmarshal(b, p); err != nil {
		return nil, 0, 0, withErrorInfo(err)
	}

	if len(p.On) == 0 {
		return nil, 0, 0, errors.New("No event triggers defined in `on`")
	}

	isCallable := ContainsEvent(w.parsed.On, flowevents.WorkflowCall)
	if !isCallable && depth > 0 {
		return nil, 0, 0, newParseError("workflow is not reusable as it is missing a `on.workflow_call` trigger")
	}

	for _, on := range w.parsed.On {
		if on.Event == flowevents.WorkflowRun {
			if on.Workflows == nil || len(*on.Workflows) == 0 {
				docsURL := runtimeHelper.GetDocsURL("/actions/learn-github-actions/events-that-trigger-workflows#workflow_run")
				return nil, 0, 0, newParseError(fmt.Sprintf("`on.workflow_run` does not reference any workflows. See %s for more information", docsURL))
			}
		}
	}

	if err := validateReservedInputAndSecretNames(p.On); err != nil {
		return nil, 0, 0, err
	}

	if err := validateJobs(p.Jobs); err != nil {
		return nil, 0, 0, err
	}

	err := validateGlobs(p.On)
	if err != nil {
		return nil, 0, 0, err
	}

	usedWorkflows := 0
	callDepth := 0
	if parseCalledWorkflows {
		calledWorkflows, childWfUsed, callDepthResult, err := PopulateJobsUsingWorkflows(ctx, p.Jobs, featureFlags, workflowSource, depth+1, runtimeHelper, actorID, obs)
		if err != nil {
			return nil, 0, 0, err
		}
		w.CalledWorkflows = calledWorkflows
		usedWorkflows = childWfUsed
		callDepth = callDepthResult
	}

	// If we don't have a proper name for the workflow, default to the filename.
	w.Name = TrimName(p.Name)
	if p.Name == "" {
		w.Name = filePath
	}

	if p.RunNameExpression.Value != "" {
		w.RunNameExpression = p.RunNameExpression.Value
	}

	if err := validateWorkflows(w.Name, w.parsed); err != nil {
		return nil, usedWorkflows, callDepth, err
	}

	if requiredworkflowutils.IsRequiredWorkflow(w.Path) {
		disallowedEvents := make([]string, 0)
		for _, on := range w.parsed.On {
			if !requiredworkflowutils.IsEventAllowedForWorkflowRulesets(on.Event) {
				disallowedEvents = append(disallowedEvents, on.Event)
			}
			if len(on.Types) > 0 {
				obs.Logger.Log(ctx, "required workflow with event types", kvp.String("gh.launch.required_workflow_event", on.Event), kvp.String("gh.launch.required_workflow_event_types", strings.Join(on.Types, ",")))
			}
		}
		if len(disallowedEvents) > 0 {
			obs.Logger.Log(ctx, "required_workflow_disallowed_events", kvp.String("gh.launch.required_workflow_disallowed_events", strings.Join(disallowedEvents, ",")))
		}
	}

	return w, usedWorkflows, callDepth, nil
}

func ContainsEvent(arr workflowOnValue, str string) bool {
	for _, s := range arr {
		if s.Event == str {
			return true
		}
	}
	return false
}

var hostedRunnerLabels = []string{"ubuntu-latest", "windows-latest", "macos-latest"}

func IsUsingHardCodedHostedRunnerLabels(parsedWorkflow *Workflow) bool {
	if parsedWorkflow == nil {
		return false
	}

	jobs := collectAllJobsForLabelsCheck(parsedWorkflow, "")

	if len(jobs) == 0 {
		return false
	}

	for _, job := range jobs {
		if !job.RunsOn.Labels.IsPresent() {
			// runs-on: is probably of mapping type, which we don't support, see runsOnConfig UnmarshalYAML
			return false
		}
		if len(job.RunsOn.Labels.Value()) == 0 {
			return false
		}
		for _, label := range job.RunsOn.Labels {
			if !slices.Contains(hostedRunnerLabels, label) {
				return false
			}
		}
	}
	return true
}

func collectAllJobsForLabelsCheck(workflow *Workflow, prefix string) jobMap {
	jobs := make(jobMap)

	// Aggregate normal jobs directly defined in the workflow
	if workflow.parsed.Jobs != nil {
		for k, job := range workflow.parsed.Jobs {
			if job.RunsOn != nil {
				// Create a unique key by prefixing the job ID
				uniqueKey := prefix + k
				jobs[uniqueKey] = job
			}
		}
	}

	// Recursively aggregate jobs from called workflows for reusable jobs
	for name, calledWorkflow := range workflow.CalledWorkflows {
		// Create a new prefix for nested workflow jobs
		nestedPrefix := prefix + name + "."
		nestedJobs := collectAllJobsForLabelsCheck(&calledWorkflow.Workflow, nestedPrefix)
		for k, job := range nestedJobs {
			// Here the key is already prefixed from the recursive call
			jobs[k] = job
		}
	}

	return jobs
}

// This returns the list of unique called workflows for given workflow jobs
func PopulateJobsUsingWorkflows(ctx context.Context, jobs jobMap, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, depth int, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (wf map[string]CalledWorkflow, calledWf, callDepth int, err error) {
	// make a list of all unique workflows being referenced
	// keep track of which job ID is using which workflow
	var (
		workflowRefToJobIDs         = make(map[string][]string)
		workflowRefToAnnotationLine = make(map[model.WorkflowRef]int)
		toFetch                     []model.WorkflowRef
		usedWorkflows               = 0
		maxCallDepth                = depth
	)

	var useSecrets, useInherit bool
	for jobID, job := range jobs {
		if job.Uses == nil {
			continue
		}
		jobSecretsTag := statter.Tags{"type": "job", "secrets": "false"}
		if job.Secrets != nil {
			jobSecretsTag["secrets"] = "true"
			jobSecretsTag["inherit"] = strconv.FormatBool(job.Secrets.Inherit)
			useSecrets = true
			useInherit = useInherit || job.Secrets.Inherit
		}
		obs.Counter(ctx, metrickeys.ReusableWorkflowSecretsInherit, jobSecretsTag, 1)
		wfRef := job.Uses.Uses
		annotationLine := job.Uses.Line
		if depth > MaxWorkflowCallDepth {
			nestedCallTags := statter.Tags{
				"call_depth": strconv.Itoa(depth),
			}
			obs.Counter(ctx, metrickeys.WorkflowCallDepthLimitError, nestedCallTags, 1)
			return nil, usedWorkflows, 0, newParseError(
				`job %q calls workflow %q, but doing so would exceed the limit on called workflow depth of %d`, jobID, wfRef.String(), MaxWorkflowCallDepth,
			)
		}

		workflowRefKey := wfRef.String()
		jobIDsUsingWorkflow, ok := workflowRefToJobIDs[workflowRefKey]
		if !ok {
			toFetch = append(toFetch, wfRef)
			usedWorkflows++
		}
		jobIDsUsingWorkflow = append(jobIDsUsingWorkflow, jobID)
		workflowRefToJobIDs[workflowRefKey] = jobIDsUsingWorkflow

		line, ok := workflowRefToAnnotationLine[wfRef]
		if !ok || line > annotationLine {
			// keep the smallest line number when the same wfRef appears in multiple places
			workflowRefToAnnotationLine[wfRef] = annotationLine
		}

		if usedWorkflows > maxWorkflowFilesReferenced(featureFlags) {
			return logAndReturnMaxWorkflowFilesReferencedError(ctx, usedWorkflows, featureFlags, obs)
		}
	}

	wfSecretsTag := statter.Tags{"type": "workflow", "secrets": "false"}
	if useSecrets {
		wfSecretsTag["secrets"] = "true"
		wfSecretsTag["inherit"] = strconv.FormatBool(useInherit)
	}
	obs.Counter(ctx, metrickeys.ReusableWorkflowSecretsInherit, wfSecretsTag, 1)

	if len(toFetch) == 0 {
		// depth is the nested level to attempt to use
		// if len(toFetch) == 0, it means that we do not have any called workflows in this depth
		maxCallDepth = depth - 1
		return nil, usedWorkflows, maxCallDepth, nil
	}

	obs.Distribution(ctx, metrickeys.WorkflowFilesReferenced, nil, float64(usedWorkflows))

	callerRepoMetadata, err := workflowSource.GetCallerRepoMetadata(ctx)
	if err != nil {
		return nil, usedWorkflows, 0, launcherror.NewInternalError(errs.Wrap(err, "resolving caller repository"))
	}

	err = workflowSource.LoadPreviousRunAttemptInfo(ctx)
	if err != nil {
		return nil, usedWorkflows, 0, launcherror.NewInternalError(errs.Wrap(err, "loading previous run attempt info"))
	}

	// fetch and parse all the workflows being referenced in parallel
	type fetchedWorkflowRes struct {
		ref           model.WorkflowRef
		metadata      RepositoryMetadata
		wf            Workflow
		usedWorkflows int
		callDepth     int
	}
	fetchWg, ctx := errgroup.WithContext(ctx)
	fetchc := make(chan fetchedWorkflowRes, len(toFetch))
	for _, wfRef := range toFetch {
		wfRef := wfRef
		// clone workflowSource so that updating it will be safe in goroutines
		wfSrc := workflowSource.Clone()
		fetchWg.Go(func() error {
			wf, metadata, usedWorkflows, callDepth, resolvedFile, err := fetchAndParseCalledWorkflow(ctx, wfRef, featureFlags, wfSrc, depth, usedWorkflows, runtimeHelper, actorID, obs, callerRepoMetadata)
			shaInfo := ""
			if err != nil {
				if launcherror.IsInternalError(err) {
					return err
				}
				if resolvedFile != nil {
					tagOrBranch := ""
					ref := types.GitRef(resolvedFile.Ref)
					if ref.IsTagRef() {
						tagOrBranch = "tag"
					} else if ref.IsHeadRef() {
						tagOrBranch = "branch"
					}
					if tagOrBranch != "" {
						shaInfo = fmt.Sprintf(" (source %v with sha:%v)", tagOrBranch, resolvedFile.SHA)
					}
				}
				// this will cancel other fetches and parses happening in parallel
				return newCalledWorkflowParseErrorWithLine(workflowRefToAnnotationLine[wfRef], err, "%q%v", wfRef.String(), shaInfo)
			}
			fetchc <- fetchedWorkflowRes{ref: wfRef, wf: *wf, usedWorkflows: usedWorkflows, callDepth: callDepth, metadata: *metadata}
			return nil
		})
	}

	if err := fetchWg.Wait(); err != nil {
		return nil, usedWorkflows, 0, err
	}
	close(fetchc)

	// map back the wfRef we fetched and parsed to the job IDs that make use of them
	calledWorkflowsByJobID := make(map[string]CalledWorkflow, len(workflowRefToJobIDs))
	for fetchedAndParsed := range fetchc {
		wfRef := fetchedAndParsed.ref
		wf := fetchedAndParsed.wf
		metadata := fetchedAndParsed.metadata
		usedWorkflows += fetchedAndParsed.usedWorkflows
		if usedWorkflows > maxWorkflowFilesReferenced(featureFlags) {
			return logAndReturnMaxWorkflowFilesReferencedError(ctx, usedWorkflows, featureFlags, obs)
		}
		jobsUsingWorkflow := workflowRefToJobIDs[wfRef.String()]
		for _, jobID := range jobsUsingWorkflow {
			calledWorkflowsByJobID[jobID] = CalledWorkflow{Workflow: wf, Metadata: metadata}
		}
		if maxCallDepth < fetchedAndParsed.callDepth {
			maxCallDepth = fetchedAndParsed.callDepth
		}
	}
	return calledWorkflowsByJobID, usedWorkflows, maxCallDepth, nil
}

func fetchAndParseCalledWorkflow(ctx context.Context, wfRef model.WorkflowRef, featureFlags types.WorkflowFeatureFlags, workflowSource WorkflowSource, depth, usedWorkflows int, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability, callerRepoMetadata *RepositoryMetadata) (*Workflow, *RepositoryMetadata, int, int, *types.ResolvedFile, error) {
	calledWorkflowFile, metadata, ok, err := workflowSource.GetWorkflowFile(ctx, wfRef, callerRepoMetadata, actorID)
	if err != nil {
		nerr := errs.Wrap(err, "failed to fetch workflow")
		if launcherror.IsNotFoundError(err) {
			// this is likely to be a user error; the called workflow is not found due to the invalid refs given by the user
			obs.Log(ctx, nerr.Error())
			return nil, nil, usedWorkflows, 0, nil, nerr
		}
		if launcherror.IsInternalError(err) {
			return nil, nil, usedWorkflows, 0, nil, nerr
		}

		// only report errors which are not due to proactive cancellation of context:
		// - context is still active ctx.Err() will be nil
		// - context has timed out ctx.Err() will context.DeadlineExceeded
		// proactive cancellation
		// - ctx.Err() will be context.Canceled
		// can happen if an error occurs while processing other called workflows
		// within the parallelization loop in PopulateJobsUsingWorkflows
		if ctx.Err() != context.Canceled {
			obs.Report(ctx, errs.Wrap(err, "error in fetching the workflow file"))
		} else {
			obs.Log(ctx, errs.Wrap(err, "this parsing run was intentionally aborted early due to failure in peer parallel parsing run").Error())
		}
		return nil, nil, usedWorkflows, 0, nil, newParseError("error in fetching the workflow file")
	}
	if !ok {
		docsURL := runtimeHelper.GetDocsURL("/actions/learn-github-actions/reusing-workflows#access-to-reusable-workflows")

		return nil, nil, usedWorkflows, 0, nil, newParseError(fmt.Sprintf("workflow was not found. See %s for more information.", docsURL))
	}

	// reset the callerRepo in the workflowSource for nested level
	workflowSource.SetCallerRepo(metadata.RepositoryID, metadata.RepositoryNWO, calledWorkflowFile.Ref, calledWorkflowFile.SHA)

	calledWorkflow, usedWorkflows, callDepth, err := parse(ctx, *calledWorkflowFile, featureFlags, workflowSource, depth, true, runtimeHelper, actorID, obs)
	if err != nil {
		return nil, nil, usedWorkflows, 0, calledWorkflowFile, err
	}

	return calledWorkflow, metadata, usedWorkflows, callDepth, calledWorkflowFile, nil
}

var lineErrorRe = regexp.MustCompile(`\bline (\d+): `)
var yamlErrorRe = regexp.MustCompile(`\byaml:`)

// ParseError represents an error with the workflow that can be attributed to a specific location
type ParseError struct {
	message string
	line    int
}

func (c ParseError) Error() string {
	if c.message != "" {
		return c.message
	}

	if c.line <= 0 {
		return "You have an error in your yaml syntax"
	}
	return fmt.Sprintf("You have an error in your yaml syntax on line %d", c.line)
}

func (c ParseError) IsUserError() bool {
	return true
}

func newParseErrorWithLine(line int, format string) ParseError {
	return ParseError{
		message: format,
		line:    line,
	}
}

func newParseError(format string, args ...any) ParseError {
	if len(args) == 0 {
		return ParseError{
			message: format,
		}
	}
	return ParseError{message: fmt.Sprintf(format, args...), line: 0}
}

// Line returns 1 indexed line number, or <= 0 if no line number present
func (c ParseError) Line() int {
	return c.line
}

// CalledWorkflowParseError represents an error with the called workflow that can be attributed to a specific location
type CalledWorkflowParseError struct {
	chain   []string
	message string
	line    int
}

func (c CalledWorkflowParseError) Error() string {
	return c.ToParseError("").Error()
}

func (c CalledWorkflowParseError) ToParseError(callerPath string) ParseError {
	message := fmt.Sprintf("error parsing called workflow\n%q\n", callerPath)
	arrowDash := ""
	for _, s := range c.chain {
		arrowDash += "-"
		message += fmt.Sprintf("%s> %s\n", arrowDash, s)
	}
	message += fmt.Sprintf(": %s", c.message)
	return ParseError{message: message, line: c.line}
}

func newCalledWorkflowParseErrorWithLine(line int, err error, format string, args ...any) CalledWorkflowParseError {
	if err, ok := err.(CalledWorkflowParseError); ok {
		return CalledWorkflowParseError{chain: append([]string{fmt.Sprintf(format, args...)}, err.chain...), message: err.message, line: line}
	}
	return CalledWorkflowParseError{chain: []string{fmt.Sprintf(format, args...)}, message: err.Error(), line: line}
}

func withErrorInfo(err error) error {
	msg := err.Error()
	matches := lineErrorRe.FindStringSubmatch(msg)
	if len(matches) < 2 {
		if yamlErrorRe.MatchString(msg) {
			return ParseError{}
		}
		return err
	}

	lineString := matches[1]
	if line, intErr := strconv.Atoi(lineString); intErr == nil {
		return ParseError{line: line}
	}

	return err
}

func validateReservedInputAndSecretNames(onStanzas workflowOnValue) error {
	failures := make([]string, 0)
	firstErrorLine := 0

	for _, on := range onStanzas {
		if on.Secrets != nil {
			for secretName, onSecret := range *on.Secrets {
				// currently only the 'workflow_call' event has the option for secrets
				if on.Event == flowevents.WorkflowCall {
					if !IsAllowedSecretName(secretName) {
						if firstErrorLine == 0 {
							firstErrorLine = onSecret.Line
						}
						failures = append(failures, fmt.Sprintf("secret name `%s` within `%s` can not be "+
							"used since it would collide with system reserved name", secretName, on.Event))
					}
				}
				// we explicitly do not erroring the use of secrets block on
				// other events for now, since it would be a breaking change
				// which can lead to misconfigured but running workflows to stop working
			}
		}
		// can later be extended for inputs as well
	}
	if len(failures) > 0 {
		return newParseErrorWithLine(firstErrorLine, strings.Join(failures, ", "))
	}
	return nil
}

func validateGlobs(onStanzas workflowOnValue) error {
	failures := make([]string, 0)
	for _, on := range onStanzas {
		keys := map[string][]string{
			"tags":            on.Tags.Value(),
			"tags-ignore":     on.TagsIgnore.Value(),
			"branches":        on.Branches.Value(),
			"branches-ignore": on.BranchesIgnore.Value(),
			"paths":           on.Paths.Value(),
			"paths-ignore":    on.PathsIgnore.Value(),
		}
		for k, globs := range keys {
			_, err := CompileV2Globs(globs)
			if err != nil {
				failures = append(failures, fmt.Sprintf("%s event contained invalid %s patterns: %s", on.Event, k, err.Error()))
			}
		}
	}
	if len(failures) > 0 {
		return errors.New(strings.Join(failures, ", "))
	}
	return nil
}

// Unmarshal and validate concurrency group name
func (c *concurrencyValue) UnmarshalYAML(unmarshal func(any) error) error {
	*c = concurrencyValue{}

	// 1. Handle the simple string case:
	// concurrency: test
	var groupName string
	if err := unmarshal(&groupName); err == nil {
		c.Group = groupName
	} else {
		// 2. Handle the object case:
		// concurrency:
		//   group: test
		//   cancel-in-progress: true
		var m map[string]string
		if err := unmarshal(&m); err == nil {
			if str, ok := m["group"]; ok {
				c.Group = str
			}
		}
	}

	if len(c.Group) > maxConcurrencyLength {
		return newParseError(fmt.Sprintf("Concurrency group name shouldn't exceed %d characters", maxConcurrencyLength))
	}

	return nil
}

// This method validates that there's no recursive loops with a
// workflow listening to itself.
func validateWorkflows(workflowName string, parsed parseTarget) error {
	for _, on := range parsed.On {
		if on.Event == flowevents.WorkflowRun {
			if on.Workflows != nil {
				for _, w := range *on.Workflows {
					if strings.EqualFold(workflowName, w) {
						return newParseError(fmt.Sprintf("Workflow '%v' cannot listen to itself.", workflowName))
					}
				}
			}
		}
	}

	return nil
}

func validateJobs(jobs jobMap) error {
	if jobs == nil {
		return errors.New("No jobs defined in `jobs`")
	}

	jobsMissingContent := make(sort.StringSlice, 0)
	jobsUsesWithStepsContent := make(sort.StringSlice, 0)
	for name, j := range jobs {
		if len(j.Steps) == 0 && j.Uses == nil {
			jobsMissingContent = append(jobsMissingContent, name)
		}
		if j.Uses != nil {
			if len(j.Steps) > 0 {
				jobsUsesWithStepsContent = append(jobsUsesWithStepsContent, name)
			}
		}
	}

	var errs []string
	if len(jobsMissingContent) > 0 {
		jobsMissingContent.Sort()
		jobsMissingContentStr := strings.Join(jobsMissingContent, ", ")
		jobsMissingContentErr := fmt.Sprintf("No steps defined in `steps` and no workflow called in `uses` for the following jobs: %s", jobsMissingContentStr)
		errs = append(errs, jobsMissingContentErr)
	}
	if len(jobsUsesWithStepsContent) > 0 {
		jobsUsesWithStepsContent.Sort()
		jobsUsesWithStepsContentStr := strings.Join(jobsUsesWithStepsContent, ", ")
		jobsUsesWithStepsContentErr := fmt.Sprintf("Cannot define both `uses` and `steps` at the same time for the following jobs: %s", jobsUsesWithStepsContentStr)
		errs = append(errs, jobsUsesWithStepsContentErr)
	}

	if len(errs) > 0 {
		return newParseError(strings.Join(errs, "\n"))
	}

	return nil
}

// Since `on` can be a string, a list of strings, or a map including both event
// descriptors and lists of schedules, we do some custom parsing and end up with
// just a list of `WorkflowOn` structs
type workflowOnValue []EventConfig

// UnmarshalYAML unmarshals an `on` value into a list of WorkflowOns
func (w *workflowOnValue) UnmarshalYAML(unmarshal func(any) error) error {
	// 1. Handle the string and string[] cases:
	// on: push
	// on: [push, issue_comment]
	var sl stringList

	if err := unmarshal(&sl); err == nil {
		*w = make(workflowOnValue, len(sl))

		for i, event := range sl {
			if !flowevents.IsAllowedEvent(event) {
				return newParseError(fmt.Sprintf("`%s` is not a valid event name", event))
			}
			(*w)[i] = EventConfig{Event: event}
		}

		return nil
	}

	// 2. Handle the map case:
	// on:
	//   push: {branches: master}
	//   schedules:
	//   - cron: * * * *
	//     branches: master
	var m map[string]onEventConfig

	scheduleParsed := model2.NewScheduleParser()

	if err := unmarshal(&m); err == nil {
		for eventName, cfg := range m {
			if eventName == "schedules" {
				return newParseError("`schedules` is not a valid event name, did you mean `schedule`?")
			}
			if !flowevents.IsAllowedEvent(eventName) {
				return newParseError(fmt.Sprintf("`%s` is not a valid event name", eventName))
			}

			values := cfg.listValues

			if eventName == flowevents.ScheduleEventName {
				if cfg.IsMap() || len(cfg.listValues) == 0 {
					return newParseError("`schedule` accepts a list of one or more maps with the `cron` key set")
				}
				for _, lv := range cfg.listValues {
					if lv.Cron == "" {
						return newParseError("`schedule` list items require the `cron` key to be set")
					}
					if _, err := scheduleParsed.ParseExpression(lv.Cron); err != nil {
						return newParseError(fmt.Sprintf("invalid `cron` attribute %q", lv.Cron))
					}
				}
			} else {
				if cfg.IsMap() {
					values = []EventConfig{*cfg.singleValue}
				} else {
					// handle the null-key case, which is parsed a list
					//
					//     on:
					//       push:
					//       issues:
					if len(cfg.listValues) > 0 {
						return newParseError(fmt.Sprintf("`%s` requires a map value", eventName))
					}
					values = []EventConfig{
						{},
					}
				}
			}

			for _, on := range values {
				// the eventName is needed within validateOn
				on.Event = eventName
				err := validateOn(on)
				if err != nil {
					return err
				}
				*w = append(*w, on)
			}

		}

		return nil
	}

	return errors.New("Invalid type for `on`")
}

// Validating `on:` Event related parameter/configuration combinations
func validateOn(on EventConfig) error {
	if on.Tags.IsPresent() && on.TagsIgnore.IsPresent() {
		return newParseError("you may only define one of `tags` and `tags-ignore` for a single event")
	}
	if on.Branches.IsPresent() && on.BranchesIgnore.IsPresent() {
		return newParseError("you may only define one of `branches` and `branches-ignore` for a single event")
	}
	if on.Paths.IsPresent() && on.PathsIgnore.IsPresent() {
		return newParseError("you may only define one of `paths` and `paths-ignore` for a single event")
	}
	/* agreed on no limits for `workflow_call`
	see https://github.com/github/c2c-actions-policy/issues/205
	if limit will be introduced later please adapt the unit test with desc -> "no limit on workflow_call inputs amount" */
	if flowevents.IsWorkflowDispatchEvent(on.Event) && on.Inputs != nil && len(*on.Inputs) > workflowDispatchInputLimit {
		// for UI rendering reasons `workflow_dispatch` is limited
		return newParseError("you may only define up to %d `inputs` for a `%s` event",
			workflowDispatchInputLimit, flowevents.WorkflowDispatch)
	}

	return nil
}

// Since a key/value pair in an `on` map can either be an event/descriptor pair
// or schedules/list-of-schedules, we parse all map values into a list of
// `WorkflowOn` structs.
type onEventConfig struct {
	listValues  []EventConfig
	singleValue *EventConfig
}

func (o *onEventConfig) UnmarshalYAML(unmarshal func(any) error) error {
	// Single parsed on node
	var p EventConfig

	if err := unmarshal(&p); err == nil {
		*o = onEventConfig{singleValue: &p}
		return nil
	}

	// List of parsed on nodes in case of schedules
	var cl []EventConfig

	if err := unmarshal(&cl); err == nil {
		*o = onEventConfig{listValues: cl}
		return nil
	}

	return newParseError("Invalid type for `on` map value")
}

func (o *onEventConfig) IsMap() bool {
	return o.singleValue != nil
}

// EventConfig represents the user configuration for a specific event
type EventConfig struct {
	Event                string
	Cron                 string      `yaml:"cron"`
	Branches             *stringList `yaml:"branches"`
	BranchesIgnore       *stringList `yaml:"branches-ignore"`
	Tags                 *stringList `yaml:"tags"`
	TagsIgnore           *stringList `yaml:"tags-ignore"`
	Paths                *stringList `yaml:"paths"`
	PathsIgnore          *stringList `yaml:"paths-ignore"`
	Workflows            *stringList `yaml:"workflows"`
	Inputs               *inputsMap  `yaml:"inputs"`
	Secrets              *secretsMap `yaml:"secrets"`
	Types                stringList  `yaml:"types"`
	ReusePreviousOutcome bool        `yaml:"reuse-previous-outcome"`
}

type inputsMap map[string]Input

// Input represents a single input for a `workflow_dispatch` event
type Input struct {
	Description string `yaml:"description"`
	Required    bool   `yaml:"required"`
	Default     string `yaml:"default"`
	Type        string `yaml:"type"`
}

type jobMap map[string]job

type job struct {
	Name        *string           `yaml:"name"`
	Uses        *usesWorkflow     `yaml:"uses"`
	Secrets     *jobSecrets       `yaml:"secrets"`
	Steps       jobStepList       `yaml:"steps"`
	RunsOn      *runsOnConfig     `yaml:"runs-on"`
	Needs       stringList        `yaml:"needs"`
	Strategy    *jobStrategy      `yaml:"strategy"`
	Environment *jobEnvironment   `yaml:"environment"`
	Concurrency *concurrencyValue `yaml:"concurrency"`
	Snapshot    *snapshotConfig   `yaml:"snapshot"`
}

type runsOnConfig struct {
	Labels stringList
}

func (r *runsOnConfig) UnmarshalYAML(unmarshal func(interface{}) error) error {
	// First, try to unmarshal as a direct slice of strings (labels)
	var labels stringList
	err := unmarshal(&labels)
	if err == nil {
		r.Labels = labels
		return nil
	}

	// If unmarshaling as a slice of strings fails, set Labels to an empty slice
	// We are not supporting/parsing mapping syntax, that is: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#example-using-groups-to-control-where-jobs-are-run
	// So set as nil
	r.Labels = nil
	// Don't return an error here, as we are not supporting the mapping syntax
	return nil
}

type snapshotConfig struct {
	ImageName string  `yaml:"image-name"`
	Version   *string `yaml:"version"`
}

func (sc *snapshotConfig) UnmarshalYAML(n *yaml.Node) error {
	// Snapshot can be just a string, the image name
	var imageName string
	if err := n.Decode(&imageName); err == nil {
		*sc = snapshotConfig{
			ImageName: imageName,
		}
		return nil
	}

	// Or an object
	var m map[string]string
	if err := n.Decode(&m); err == nil {
		if str, ok := m["image-name"]; ok {
			sc.ImageName = str
		}
		if str, ok := m["version"]; ok {
			sc.Version = &str
		}
		return nil
	}

	return newParseErrorWithLine(n.Line, "Invalid type for `job.snapshot`")
}

type usesWorkflow struct {
	Uses model.WorkflowRef
	Line int
}

func (uw *usesWorkflow) UnmarshalYAML(n *yaml.Node) error {
	var rawUses string

	if err := n.Decode(&rawUses); err != nil {
		return err
	}
	usesRef, err := model.ParseWorkflowRef(rawUses)
	if err != nil {
		return newParseErrorWithLine(n.Line, fmt.Sprintf("invalid value workflow reference: %s", err.Error()))
	}
	uw.Uses = *usesRef
	uw.Line = n.Line
	return nil
}

type jobSecrets struct {
	// the property "secrets" is not used anywhere but we are keeping it to avoid confusion
	// because when w parse jobSecrets it will be either inherit or secrets map
	secrets map[string]string
	Inherit bool
}

func (js *jobSecrets) UnmarshalYAML(n *yaml.Node) error {
	// secrets can be either 'inherit' or a map of secrets
	var rawSecrets string
	err := n.Decode(&rawSecrets)
	if err == nil && rawSecrets == "inherit" {
		js.Inherit = true
		return nil
	}

	var secretsMap map[string]string
	if err = n.Decode(&secretsMap); err != nil {
		return newParseErrorWithLine(n.Line, "invalid value for secrets. Expected \"inherit\" keyword or explicit map of secrets")
	}
	js.secrets = secretsMap

	return nil
}

type jobStepList []parsedStep

type jobStrategy struct {
	Matrix     jobMatrix
	Expression string
}
type jobEnvironment struct {
	Name      string
	IsDynamic bool
}

type jobMatrix any

var dynamicStringRe = regexp.MustCompile(`\${{.*}}`)

func containsExpression(input string) bool {
	return dynamicStringRe.MatchString(input)
}

func (j *jobEnvironment) UnmarshalYAML(unmarshal func(any) error) error {
	*j = jobEnvironment{}

	// Environment can be just a string
	var environmentName string
	if err := unmarshal(&environmentName); err == nil {
		j.Name = environmentName
	} else {
		// Or an object
		var m map[string]string
		if err := unmarshal(&m); err == nil {
			if str, ok := m["name"]; ok {
				j.Name = str
			}
		}
	}

	if j.Name != "" {
		j.IsDynamic = containsExpression(j.Name)

		return nil
	}

	return newParseError("Invalid type for `job.environment`")
}

func (j *jobStrategy) UnmarshalYAML(unmarshal func(any) error) error {
	*j = jobStrategy{}

	if str, err := unmarshalString(unmarshal); err == nil {
		j.Expression = str
		return nil
	}

	var strategyMap map[string]any
	if err := unmarshal(&strategyMap); err == nil {
		if v, ok := strategyMap["matrix"]; ok {
			j.Matrix = v
		}
		return nil
	}

	return newParseError("Invalid type for `job.strategy`")
}

func (j *jobStepList) UnmarshalYAML(unmarshal func(any) error) error {
	var p []parsedStep
	err := unmarshal(&p)
	if err, ok := err.(userFacingParseError); ok {
		return err
	}
	if err != nil {
		return newParseError("Invalid `steps` value - steps should be list of `uses` or `run` items")
	}

	*j = make(jobStepList, len(p))
	copy(*j, p)
	return nil
}

type parsedStep struct {
	Uses model.Uses
}

// Currently the only field parsed is the `uses` of valid uses actions as it's all we need,
// all other actions are zero parsedAction structs
func (p *parsedStep) UnmarshalYAML(unmarshal func(any) error) error {
	*p = parsedStep{}

	var rawAction struct {
		Uses *string
		Run  *string
	}

	// ignore invalid values, or string actions which can't unmarshal to the above
	// (implicitly shell actions, e.g `steps: ["echo foo bar", ...`)
	if err := unmarshal(&rawAction); err != nil {
		return nil
	}

	key := ""
	handleTypeKey := func(s string, v *string) {
		// when key is not present (or explicitly set to `:null`)
		if v == nil {
			return
		}
		if key == "" {
			key = s
		} else {
			// ambiguous action as it has more than one of the type-identifying keys
			key = "ambiguous"
		}
	}

	handleTypeKey("run", rawAction.Run)
	handleTypeKey("uses", rawAction.Uses)

	if key == "uses" {
		u, err := model.ParseActionRef(*rawAction.Uses)
		if err != nil {
			return userFacingParseError{msg: err.Error()}
		}

		p.Uses = u
	}

	if key == "ambiguous" {
		return userFacingParseError{"a step cannot have both the `uses` and `run` keys"}
	}

	if key == "" {
		return userFacingParseError{"every step must define a `uses` or `run` key"}
	}

	return nil
}

func (sl *stringList) HasGlobs() bool {
	return sl != nil && len(*sl) > 0
}

type userFacingParseError struct {
	msg string
}

func (u userFacingParseError) Error() string {
	return u.msg
}

func TrimName(name string) string {
	if len(name) <= maxNameLength {
		return name
	}

	// Truncating the slice could result in a multi-byte character being
	// truncated in the middle.
	return strings.ToValidUTF8(name[:maxNameLength-3], "") + trimmedTextMarker
}

func maxWorkflowFilesReferenced(featureFlags types.WorkflowFeatureFlags) int {
	if featureFlags.IncreasedMaxWorkflowFilesReferencedEnabled {
		return maxWorkflowFilesReferencedIncreased
	}
	return maxWorkflowFilesReferencedStandard
}

func logAndReturnMaxWorkflowFilesReferencedError(ctx context.Context, usedWorkflows int, featureFlags types.WorkflowFeatureFlags, obs *observability.Observability) (wf map[string]CalledWorkflow, calledWf, callDepth int, err error) {
	tags := statter.Tags{
		"limit":      strconv.Itoa(maxWorkflowFilesReferenced(featureFlags)),
		"references": strconv.Itoa(usedWorkflows),
	}
	obs.Counter(ctx, metrickeys.WorkflowFilesReferencedLimitError, tags, 1)
	return nil, usedWorkflows, 0, newParseError("too many workflows are referenced, total: %d, limit: %d", usedWorkflows, maxWorkflowFilesReferenced(featureFlags))
}

func fileReferenceFromFile(file types.ResolvedFile) types.WorkflowFileReference {
	if requiredworkflowutils.IsRequiredWorkflow(file.Path) {
		return types.NewRulesetWorkflowFileReference(file.Path, types.GitRef(file.Ref), types.CommitSha(file.SHA))
	}

	return types.NewWorkflowFileReference(file.Path)
}
