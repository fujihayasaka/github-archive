package workflowinvoker

import (
	"strings"

	githubgo "github.com/google/go-github/v25/github"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
)

type WorkflowSelector struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	// EventName restricts workflows to a single event type
	EventName string

	// WorkflowFile allows optionally restricting workflows to a single file
	Path *string

	// WorkflowIdentifier is only used for WorkflowRun events. Workflows with the given
	// identifier will _not_ be selected.
	WorkflowIdentifier string
}

// NewWorkflowSelector returns a new workflow selector for the given event name and event
func NewWorkflowSelector(eventName string, event flowevents.GitHubEvent) WorkflowSelector {
	var selector = WorkflowSelector{
		EventName: eventName,
	}

	if workflowDispatch, ok := event.(*githubgo.WorkflowDispatchEvent); ok {
		workflowPath := workflowDispatch.GetWorkflow()
		selector.Path = &workflowPath
	}

	if workflowRun, ok := event.(*githubgo.WorkflowRunEvent); ok {
		selector.WorkflowIdentifier = workflowRun.GetWorkflow().Name
	}

	return selector
}

// Select returns matching workflows from given configuration
func (ws *WorkflowSelector) Select(config *model.Configuration) ([]*model.Workflow, error) {
	if ws.EventName == flowevents.Dynamic {
		// All workflows support the dynamic event
		return config.Workflows, nil
	}

	result := make([]*model.Workflow, 0)

	// Select by event
	for _, workflowCandidate := range config.Workflows {
		if workflowCandidate.On.String() == ws.EventName {
			// filter out a workflow that is activating itself.
			if ws.EventName == flowevents.WorkflowRun {
				if !strings.EqualFold(workflowCandidate.Identifier, ws.WorkflowIdentifier) {
					result = append(result, workflowCandidate)
				}
			} else {
				result = append(result, workflowCandidate)
			}
		}
	}

	// Filter to single workflow if given
	if ws.Path != nil {
		for _, r := range result {
			if r.Path == *ws.Path {
				// Stop after finding a first matching workflow
				return []*model.Workflow{r}, nil
			}
		}

		return []*model.Workflow{}, nil
	}

	return result, nil
}
