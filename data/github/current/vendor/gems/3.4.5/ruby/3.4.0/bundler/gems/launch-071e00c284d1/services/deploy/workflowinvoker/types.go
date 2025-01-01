package workflowinvoker

import (
	"encoding/json"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

func NewInvocation(
	event InvokingEvent,
	executingActor InvokingActor,
	triggerActor InvokingActor,
	target invocationTarget,
	opts ...InvocationOption,
) Invocation {
	i := Invocation{
		Event:           event,
		ExecutingActor:  executingActor,
		TriggeringActor: triggerActor,
		Target:          target,
	}

	for _, opt := range opts {
		opt(&i)
	}
	return i
}

var (
	// these stanzas are compile-time checks to ensure that the invocation type properly implements JSON enc/decoding
	_ json.Marshaler   = Invocation{}
	_ json.Unmarshaler = &Invocation{}
)

type Invocation struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	Event           InvokingEvent
	ExecutingActor  InvokingActor
	TriggeringActor InvokingActor
	Target          invocationTarget

	// ExistingCheckSuite indicates that this Invocation is for a re-run and that there is an existing check suite
	ExistingCheckSuite     *types.CheckSuiteState
	ExistingExecutionID    *types.WorkflowExecutionID
	RerunWebhookDeliveryID string
	RerunInfo              *types.RerunInfo
	EnableDebugLogging     bool

	// PrecreatedCheckSuiteID identifies the check suite that should be used for this new run (not a re-run)
	PrecreatedCheckSuiteID *types.GlobalID
}

type wireFormat struct {
	Event                  *InvokingEvent              `json:"Event"`
	Actor                  *InvokingActor              `json:"Actor,omitempty"`
	ExecutingActor         *InvokingActor              `json:"ExecutingActor,omitempty"`
	TriggeringActor        *InvokingActor              `json:"TriggeringActor,omitempty"`
	Target                 *invocationTarget           `json:"Target"`
	ExistingCheckSuite     **types.CheckSuiteState     `json:"ExistingCheckSuite"`
	ExistingExecutionID    **types.WorkflowExecutionID `json:"ExistingExecutionID"`
	RerunWebhookDeliveryID *string                     `json:"RerunWebhookDeliveryID"`
	RerunInfo              **types.RerunInfo           `json:"RerunInfo"`
	PrecreatedCheckSuiteID **types.GlobalID            `json:"PrecreatedCheckSuiteID"`
}

func (i *Invocation) UnmarshalJSON(p []byte) error {
	// if you change anything here, ensure to cover the change with a forward-and-backward compatibility test
	// as exampled here: https://github.com/github/launch/commit/8842f906c079edc4f8bb8ac2ddbf6373c386cb89#diff-520337f46de8474ed51a5b609fa4dedd8d6b8f4f9404067cc840c09b54301622R17
	wireFormat := wireFormat{
		Event:                  &i.Event,
		Actor:                  nil,
		ExecutingActor:         &i.ExecutingActor,
		TriggeringActor:        &i.TriggeringActor,
		Target:                 &i.Target,
		ExistingCheckSuite:     &i.ExistingCheckSuite,
		ExistingExecutionID:    &i.ExistingExecutionID,
		RerunWebhookDeliveryID: &i.RerunWebhookDeliveryID,
		RerunInfo:              &i.RerunInfo,
		PrecreatedCheckSuiteID: &i.PrecreatedCheckSuiteID,
	}
	if err := json.Unmarshal(p, &wireFormat); err != nil {
		return err
	}
	if wireFormat.Actor != nil { // backward compatibility for transition from `"Actor"` to `"{Executing|Triggering}Actor"`
		i.ExecutingActor = *wireFormat.Actor
		i.TriggeringActor = *wireFormat.Actor
	}
	return nil
}

func (i Invocation) MarshalJSON() ([]byte, error) {
	out := wireFormat{
		Event:                  &i.Event,
		Actor:                  &i.ExecutingActor, // for forward compatibility, this will get encoded and filled using `Actor` if it exists
		ExecutingActor:         &i.ExecutingActor,
		TriggeringActor:        &i.TriggeringActor,
		Target:                 &i.Target,
		ExistingCheckSuite:     &i.ExistingCheckSuite,
		ExistingExecutionID:    &i.ExistingExecutionID,
		RerunWebhookDeliveryID: &i.RerunWebhookDeliveryID,
		RerunInfo:              &i.RerunInfo,
		PrecreatedCheckSuiteID: &i.PrecreatedCheckSuiteID,
	}
	return json.Marshal(out)
}

// ExecutionID returns an existing execution ID or generates a new one
func (i *Invocation) ExecutionID() types.WorkflowExecutionID {
	if i.ExistingExecutionID != nil {
		return *i.ExistingExecutionID
	}

	return types.NewRandomWorkflowExecutionID()
}

// If we have a NewWebhookDelieveryID that will be returned (this is a rerun),
// otherwise the original one from the Event will be returned.
func (i *Invocation) LatestWebhookDeliveryID() *string {
	if i.RerunWebhookDeliveryID != "" {
		return &i.RerunWebhookDeliveryID
	}
	return i.Event.WebhookDeliveryID
}

type InvocationOption func(*Invocation)

// WithExecutionID applies the given execution ID to the invocation.
func WithExecutionID(id types.WorkflowExecutionID) InvocationOption {
	return func(e *Invocation) {
		e.ExistingExecutionID = &id
	}
}

// WithCheckSuiteState applies the given check suite state to the invocation.
func WithCheckSuiteState(state *types.CheckSuiteState) InvocationOption {
	return func(e *Invocation) {
		e.ExistingCheckSuite = state
	}
}

// WithRerunWebhookDeliveryID applies the given RerunWebhookDeliveryID to the invocation.
func WithRerunWebhookDeliveryID(id string) InvocationOption {
	return func(e *Invocation) {
		e.RerunWebhookDeliveryID = id
	}
}

// WithRerunInfo applies the given RerunInfo to the invocation.
func WithRerunInfo(info *types.RerunInfo) InvocationOption {
	return func(e *Invocation) {
		e.RerunInfo = info
	}
}

// WithEnableDebugLogging applies the given enableDebugLogging boolean to the invocation.
func WithEnableDebugLogging(enableDebugLogging bool) InvocationOption {
	return func(e *Invocation) {
		e.EnableDebugLogging = enableDebugLogging
	}
}

func NewTarget(
	repositoryID types.GlobalID,
	repositoryDatabaseID int64,
	workflowSelector WorkflowSelector,
	repositoryOwnerGlobalID types.GlobalID,
	repositoryOwnerDatabaseID int64,
	githubTenant ghtenant.GitHubTenant,
) invocationTarget {
	return invocationTarget{
		RepositoryID:              repositoryID,
		RepositoryDatabaseID:      repositoryDatabaseID,
		WorkflowSelector:          workflowSelector,
		RepositoryOwnerGlobalID:   repositoryOwnerGlobalID,
		RepositoryOwnerDatabaseID: repositoryOwnerDatabaseID,
		GitHubTenant:              githubTenant,
	}
}

// invocationTarget specifies what we're running against
type invocationTarget struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	RepositoryID         types.GlobalID
	RepositoryDatabaseID int64

	WorkflowSelector          WorkflowSelector
	RepositoryOwnerGlobalID   types.GlobalID
	RepositoryOwnerDatabaseID int64
	GitHubTenant              ghtenant.GitHubTenant
}

func NewActor(
	ID types.GlobalID,
	login string,
) InvokingActor {
	return InvokingActor{
		ID:    ID,
		Login: login,
	}
}

type InvokingActor struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`
	ID    types.GlobalID `json:"ID"`
	Login string         `json:"Login"`
}

func NewEvent(
	webhookDeliveryID *string,
	ref types.GitRef,
	commit types.CommitSha,
	commitMessage types.CommitMessage,
	event string,
	eventAction string,
	payload []byte,
	eventTime time.Time,
	eventOriginTime time.Time,
	ghe flowevents.GitHubEvent,
) InvokingEvent {
	return InvokingEvent{
		WebhookDeliveryID: webhookDeliveryID,
		Ref:               ref,
		Commit:            commit,
		CommitMessage:     commitMessage,
		Name:              event,
		Action:            eventAction,
		Payload:           payload,
		Time:              eventTime,
		OriginTime:        eventOriginTime,
		Ghe:               ghe,
	}
}

type InvokingEvent struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	// WebhookDeliveryID is a unique identifier for this event. It's
	// - generated by `gh/gh` when the event is a webhook event
	// - generated by launch when the event is a schedule event
	WebhookDeliveryID *string

	Ref types.GitRef
	// Note: this can be a NilCommitSha, for events not associated with a commit (e.g repository_dispatch)
	Commit types.CommitSha
	// Note: this can be a CommitMessageZeroValue if the event didn't already contain the message.
	CommitMessage types.CommitMessage
	Name          string
	Action        string
	Payload       []byte
	Time          time.Time
	// OriginTime is the earliest recorded time for this event.
	OriginTime time.Time

	Ghe flowevents.GitHubEvent `json:"-"`
}

type innerInvokingEvent InvokingEvent

func (ie *InvokingEvent) UnmarshalJSON(data []byte) error {
	var event innerInvokingEvent
	if err := json.Unmarshal(data, &event); err != nil {
		return err
	}

	switch event.Name {
	case flowevents.ScheduleEventName:
		event.Ghe = &flowevents.ScheduleEvent{}

	case flowevents.Dynamic:
		event.Ghe = &flowevents.DynamicEvent{}
		if err := json.Unmarshal(event.Payload, &event.Ghe); err != nil {
			return err
		}

		// no case for flowevents.WorkflowCall, as it not a real trigger

	default:
		ghe, err := flowevents.ParseEventWebHook(event.Name, event.Payload)
		if err != nil {
			return err
		}

		event.Ghe = ghe
	}

	*ie = InvokingEvent(event)

	return nil
}

func EventFromPersistedPayload(eventType string, payload []byte) (flowevents.GitHubEvent, error) {
	if flowevents.IsAllowedWebhookEvent(eventType) {
		eventName := flowevents.ResolveSyntheticEventName(eventType)
		gitHubEvent, err := flowevents.ParseEventWebHook(eventName, payload)
		if err != nil {
			return nil, err
		}

		return gitHubEvent, nil
	}

	if eventType == flowevents.ScheduleEventName {
		return &flowevents.ScheduleEvent{}, nil
	}

	if eventType == flowevents.Dynamic {
		var dynamicEvent *flowevents.DynamicEvent
		err := json.Unmarshal(payload, &dynamicEvent)
		if err != nil {
			return nil, err
		}

		return dynamicEvent, nil
	}

	return nil, errors.Errorf("unable to handle event: %s", eventType)
}
