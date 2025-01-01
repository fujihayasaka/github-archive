package flowevents

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/actions-expressions/go/data"

	"github.com/github/launch/observability"
)

// WorkflowEventPayload unmarshals a workflow event (webhook or non-webhook) payload and prepares
// it so it can be passed to Actions Service.
func WorkflowEventPayload(eventType string, payload []byte) (map[string]any, error) {
	var eventPayload map[string]any

	if err := json.Unmarshal(payload, &eventPayload); err != nil {
		return nil, err
	}

	switch eventType {
	case Dynamic:
		// Remove data from the payload that we do not want to make available to the workflow run
		delete(eventPayload, "workflow")
		delete(eventPayload, "integration_name")
		delete(eventPayload, "workflow_name")
		delete(eventPayload, "slug")
	}

	return eventPayload, nil
}

// WorkflowEventContext unmarshals a workflow event (webhook or non-webhook) payload and prepares
// it so it can be used when evaluating expressions and can also be passed to Run Service.
func WorkflowEventContext(ctx context.Context, obs *observability.Observability, eventType string, payload []byte) (*data.Dictionary, error) {
	d, err := data.DecodeDictionary(string(payload))
	if err != nil {
		return nil, fmt.Errorf("decode workflow event payload: %w", err)
	}

	switch eventType {
	case Dynamic:
		// Remove data from the payload that we do not want to make available to the workflow run
		d2 := data.NewDictionary()
		for _, p := range d.Pairs() {
			switch p.Key {
			case "workflow", "integration_name", "workflow_name", "slug":
				continue
			default:
				d2.Add(p.Key, p.Value)
			}
		}
		d = d2
	}

	return d, nil
}
