// functions to help determine the severity of unhandled errors.
package workflowinvoker

import (
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/flow/flowevents/eventactions"
)

type eventTriggersRun string

const (
	eventTriggersRunLikely   eventTriggersRun = "likely"
	eventTriggersRunUnlikely eventTriggersRun = "unlikely"
	eventTriggersRunYes      eventTriggersRun = "yes"
)

func (e eventTriggersRun) String() string { return string(e) }

// Make a cheap guess if this event is likely to match a workflow and trigger a run.
func guessIfEventTriggersRun(event InvokingEvent) eventTriggersRun {
	if event.Action == eventactions.Rerequested {
		return eventTriggersRunYes
	}

	if event.Name == flowevents.Schedule {
		return eventTriggersRunYes
	}

	if event.Name == flowevents.RepositoryDispatch ||
		event.Name == flowevents.WorkflowDispatch ||
		event.Name == flowevents.Push ||
		event.Name == flowevents.PullRequest {
		// check if the event action is one of the defaults (synchronize, etc).
		defaultActions := flowevents.GetEventTypeGlobs(event.Name)

		if defaultActions == nil {
			return eventTriggersRunLikely
		}

		for _, defaultAction := range defaultActions {
			if event.Action == defaultAction {
				return eventTriggersRunLikely
			}
		}
	}

	return eventTriggersRunUnlikely
}
