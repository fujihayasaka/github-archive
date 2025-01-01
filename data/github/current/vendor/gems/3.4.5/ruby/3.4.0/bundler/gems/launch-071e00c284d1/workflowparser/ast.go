package workflowparser

import (
	"encoding/json"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/requiredworkflowutils"
)

// Workflow is a struct giving access to the logical structure of our workflow file
type Workflow struct {
	Name              string
	RunNameExpression string
	Path              string
	File              types.ResolvedFile
	parsed            parseTarget
	FileReference     types.WorkflowFileReference

	CalledWorkflows map[string]CalledWorkflow
}

func (w *Workflow) Parsed() parseTarget {
	return w.parsed
}

func (w *Workflow) IsRequiredWorkflow() bool {
	return requiredworkflowutils.IsRequiredWorkflow(w.Path)
}

type ReferencedWorkflow struct {
	Path string `json:"path"`
	Sha  string `json:"sha"`
	Ref  string `json:"ref,omitempty"`
}

func (w *Workflow) BuildReferencedWorkflowsJSON() (string, error) {
	referencedWorkflowsMap := make(map[string]ReferencedWorkflow)
	addReferencedWorkflows(w.CalledWorkflows, referencedWorkflowsMap, 1)

	referencedWorkflows := make([]ReferencedWorkflow, 0, len(referencedWorkflowsMap))
	for _, workflow := range referencedWorkflowsMap {
		referencedWorkflows = append(referencedWorkflows, workflow)
	}

	if len(referencedWorkflows) == 0 {
		return "", nil
	}

	res, err := json.Marshal(referencedWorkflows)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func addReferencedWorkflows(calledWorkflows map[string]CalledWorkflow, referencedWorkflows map[string]ReferencedWorkflow, depth int) {
	if depth > MaxWorkflowCallDepth {
		return
	}

	for _, workflow := range calledWorkflows {
		if _, ok := referencedWorkflows[workflow.Workflow.Path]; ok {
			continue
		}
		referencedWorkflows[workflow.Workflow.Path] = ReferencedWorkflow{
			Path: workflow.Workflow.Path,
			Sha:  workflow.Workflow.File.SHA,
			Ref:  workflow.Workflow.File.Ref,
		}
		addReferencedWorkflows(workflow.Workflow.CalledWorkflows, referencedWorkflows, depth+1)
	}
}

// CalledWorkflow wraps a workflow and its reference
type CalledWorkflow struct {
	Workflow Workflow
	Metadata RepositoryMetadata
}

func (w *Workflow) GetCronExpressions() []string {
	es := make([]string, 0)
	for _, on := range w.parsed.On {
		if on.Event == flowevents.ScheduleEventName {
			es = append(es, on.Cron)
		}
	}
	return es
}

// OnForEvent returns a bool indicating whether the workflow listens for the given event
func (w *Workflow) OnForEvent(event string) (EventConfig, bool) {
	if event == flowevents.Dynamic {
		// All workflows listen to the dynamic event
		return EventConfig{
			Event: flowevents.Dynamic,
		}, true
	}

	if requiredworkflowutils.IsRequiredWorkflow(w.Path) {
		// Ignore ignore event filters for required workflows
		return EventConfig{
			Event: event,
		}, true
	}

	for _, on := range w.parsed.On {
		if event == on.Event {
			return on, true
		}
	}
	return EventConfig{}, false
}

func (w *Workflow) ReusePreviousOutcomeForEvent(event string) bool {
	for _, on := range w.parsed.On {
		if event == on.Event && on.ReusePreviousOutcome {
			return true
		}
	}
	return false
}

func (w *Workflow) Jobs() []*model.Job {
	jobs := make([]*model.Job, 0, len(w.parsed.Jobs))

	for jobID, job := range w.parsed.Jobs {
		var name *string
		if job.Name != nil && !containsExpression(*job.Name) {
			name = job.Name
		}

		jobs = append(jobs, &model.Job{
			ID:          jobID,
			Name:        name,
			Needs:       job.Needs.Value(),
			Strategy:    getStrategy(&job),
			Environment: getEnvironment(&job),
		})
	}

	return jobs
}

func getStrategy(j *job) *model.Strategy {
	var strategy *model.Strategy
	if j.Strategy != nil {
		var matrix *model.Matrix
		if j.Strategy.Matrix != nil {
			m := model.Matrix(j.Strategy.Matrix)
			matrix = &m
		}
		strategy = &model.Strategy{Matrix: matrix}

		if j.Strategy.Expression != "" {
			strategy.Expression = j.Strategy.Expression
		}
	}
	return strategy
}

func getEnvironment(j *job) *model.Environment {
	var env *model.Environment
	if j.Environment != nil {
		env = &model.Environment{
			Name:      j.Environment.Name,
			IsDynamic: j.Environment.IsDynamic,
		}
	}
	return env
}

// GetActions returns an array of the actions found in the workflow.
func (w *Workflow) GetActions() []*model.Action {
	actions := make([]*model.Action, 0)

	for _, step := range w.getSteps() {
		if step.Uses == nil {
			continue
		}
		actions = append(actions, &model.Action{
			Uses: step.Uses,
		})

	}
	return actions
}

// WorkflowToConfiguration turns a single Workflow into a model.Configuration.
//
// We can bridge the gap between the two models because:
// - existing workflow files have many workflows per file,
// - pipelines have one workflow per file (with >= 1 triggers) but many files.
//
// So in both cases we have many workflows, and we can abstract over the
// number of files.
func WorkflowToConfiguration(w *Workflow) model.Configuration {
	c := model.Configuration{
		Workflows: make([]*model.Workflow, 0),
	}

	c.Actions = w.GetActions()

	// without triggers, there's nothing to queue
	triggers := w.convertOn()
	if len(triggers) == 0 {
		return c
	}

	// append workflow for each trigger in the file, we're not worried about dupes
	// as for planning we simply need to know if there are 1+ triggers for an event
	for _, trig := range triggers {
		wf := model.Workflow{
			Identifier:        w.Name,
			RunNameExpression: w.RunNameExpression,
			On:                trig,
			Path:              w.Path,
			File:              w.File,
			FileReference:     w.FileReference,
		}

		c.Workflows = append(c.Workflows, &wf)
	}

	return c
}

type GlobFilterSpec struct {
	Sequence  []string `json:"globs"`
	IsInclude bool     `json:"isInclude"`
}

func InclusiveSpec(sequence []string) *GlobFilterSpec {
	return &GlobFilterSpec{Sequence: sequence, IsInclude: true}
}

func (w *Workflow) PathFilters(event string) *GlobFilterSpec {
	trig, ok := w.OnForEvent(event)
	if !ok {
		return nil
	}

	// we validate XOR between these two in validateOn

	if trig.Paths.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  trig.Paths.Value(),
			IsInclude: true,
		}
	}

	if trig.PathsIgnore.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  trig.PathsIgnore.Value(),
			IsInclude: false,
		}
	}

	return nil
}

func (ec *EventConfig) BranchFilters() *GlobFilterSpec {
	// we validate XOR between these two in validateOn
	if ec.Branches.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  ec.Branches.Value(),
			IsInclude: true,
		}
	}

	if ec.BranchesIgnore.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  ec.BranchesIgnore.Value(),
			IsInclude: false,
		}
	}

	return nil
}

func (ec *EventConfig) TagFilters() *GlobFilterSpec {
	// we validate XOR between these two in validateOn
	if ec.Tags.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  ec.Tags.Value(),
			IsInclude: true,
		}
	}

	if ec.TagsIgnore.IsPresent() {
		return &GlobFilterSpec{
			Sequence:  ec.TagsIgnore.Value(),
			IsInclude: false,
		}
	}

	return nil
}

func (w *Workflow) convertOn() []model.On {
	ts := make([]model.On, 0)
	for _, on := range w.parsed.On {
		var p model.On
		// we can't fulfil the `On()` interface, but we can convert
		if on.Event == flowevents.ScheduleEventName {
			p = &model.OnSchedule{
				Expression: on.Cron,
			}
		} else if on.Event != "" {
			p = &model.OnEvent{
				Event: on.Event,
			}
		} else {
			p = &model.OnInvalid{}
		}
		ts = append(ts, p)
	}
	return ts
}

func (w *Workflow) getSteps() []parsedStep {
	acts := make([]parsedStep, 0)
	for jobID, job := range w.parsed.Jobs {
		if job.Uses != nil {
			usedWorkflow := w.CalledWorkflows[jobID]
			acts = append(acts, usedWorkflow.Workflow.getSteps()...)
		} else {
			for _, a := range job.Steps {
				acts = append(acts, a)
			}
		}
	}
	return acts
}
