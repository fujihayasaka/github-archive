package types

import (
	"github.com/pkg/errors"
)

// CheckSuiteState stores the current state of a check suite
type CheckSuiteState struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	WorkflowBuildDatabaseID int64

	// Source repository/commit for flow file:
	RepositoryID      GlobalID
	EventSHA          CommitSha
	EventRef          GitRef
	CheckoutSHA       CommitSha
	CheckoutRef       GitRef
	ExecutedAsActorID GlobalID

	// The user-provided name of the flow within the flow file: i.e. `workflow "FlowIdentifier" { }`
	FlowIdentifier string

	WebhookDeliveryID *string
	Event             string
	EventAction       string
	EventPayload      []byte

	CheckSuiteIDPair IDPair
	WorkflowFilePath string
	WorkflowFileRef  GitRef // used for ruleset workflows only

	WorkflowRunID      int64
	WorkflowRunNumber  int64
	WorkflowRunAttempt int64

	TriggerID GlobalID

	ExecutionID WorkflowExecutionID
	Backend     WorkflowBackend
}

// NewCheckSuiteState create a checkSuite
func NewCheckSuiteState(repositoryID GlobalID, eventSHA CommitSha, eventRef GitRef, checkoutSHA CommitSha, checkoutRef GitRef, headRepositoryID GlobalID, flowIdentifier, workflowFilePath string, workflowRunID int64, workflowRunNumber int64, triggerID GlobalID, workflowFileRef GitRef) (*CheckSuiteState, error) {
	if repositoryID == NilGlobalID {
		return nil, errors.New("repositoryID required")
	}
	if eventSHA.IsZeroValue() {
		return nil, errors.New("eventSHA required")
	}
	if headRepositoryID == NilGlobalID {
		return nil, errors.New("headRepositoryID required")
	}
	if eventSHA.IsNullSha() {
		return nil, errors.New("non-zero eventSHA required")
	}
	suite := CheckSuiteState{
		RepositoryID:      repositoryID,
		EventSHA:          eventSHA,
		EventRef:          eventRef,
		CheckoutSHA:       checkoutSHA,
		CheckoutRef:       checkoutRef,
		FlowIdentifier:    flowIdentifier,
		WorkflowFilePath:  workflowFilePath,
		WorkflowRunID:     workflowRunID,
		WorkflowRunNumber: workflowRunNumber,
		TriggerID:         triggerID,
		WorkflowFileRef:   workflowFileRef,
	}
	return &suite, nil
}
