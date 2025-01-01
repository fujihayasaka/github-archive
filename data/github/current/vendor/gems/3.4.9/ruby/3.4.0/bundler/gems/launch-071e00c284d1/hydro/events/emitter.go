package events

import (
	"context"
	"log"
	"sync"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
)

// Emitter synchronously or asynchronously publishes events to a hydro publisher.
type Emitter struct {
	publisher Publisher
	log       logger.Logger
	stats     statter.Statter

	once   sync.Once
	events chan Event
	done   chan struct{}
}

const maxQueuedEvents = 15000

// an interface to make mocking Emitter possible - if possible have your service accept a Hydro not (*Emitter)
type Hydro interface {
	Emit(event Event)
	CountErroredEvent(eventType string)
}

// NewEmitter creates a Emitter instance that can synchronously or asynchronously send events to hydro.
//
// One of the Publisher options must be specified.
func NewEmitter(opts ...EmitterOption) (*Emitter, error) {
	e := &Emitter{}
	for _, opt := range opts {
		opt(e)
	}
	if e.publisher == nil {
		return nil, errors.New("You must specify a publisher! (See 'go doc events.EmitterOption'.)")
	}
	if e.log == nil {
		e.log = logger.NullLogger()
	}
	if e.stats == nil {
		e.stats = statter.NullStatter()
	}
	return e, nil
}

// Close shuts down the emitter.
func (e *Emitter) Close() {
	if e.events != nil {
		close(e.events)
	}
	if e.done != nil {
		<-e.done
	}
}

// EmitBlocking publishes an event synchronously.
func (e *Emitter) EmitBlocking(ctx context.Context, event Event) error {
	err := e.publisher.Publish(ctx, event.GetHydroMessages(), "")
	if err != nil {
		return err
	}

	e.countEvent("emitted", event.GetEventType())
	return nil
}

// EmitBlockingWithPartitionKey publishes an event synchronously with a partition key.
func (e *Emitter) EmitBlockingWithPartitionKey(ctx context.Context, event Event, partitionKey string) error {
	err := e.publisher.Publish(ctx, event.GetHydroMessages(), partitionKey)
	if err != nil {
		return err
	}

	e.countEvent("emitted", event.GetEventType())
	return nil
}

// Emit publishes an event asynchronously.
func (e *Emitter) Emit(event Event) {
	// If Emit is called after Close, 'e.events <- event' will panic.
	defer func() {
		if r := recover(); r != nil {
			e.countEvent("panic", event.GetEventType())
			e.safeReport(kvperrors.With("panic when emitting event!"), event.GetEventType())
		}
	}()

	// Set up the channel
	e.once.Do(e.setupAsyncEmit)

	// Post the event, but don't block if the channel is full.
	select {
	case e.events <- event:
		e.recordQueued()
	default:
		e.countEvent("dropped", event.GetEventType())
		e.safeReport(kvperrors.With("event dropped!"), event.GetEventType())
	}
}

func (e *Emitter) setupAsyncEmit() {
	e.events = make(chan Event, maxQueuedEvents)
	e.done = make(chan struct{})
	go func() {
		for event := range e.events {
			// Using background since async event doesn't care about original ctx being propagated
			if err := e.EmitBlocking(context.Background(), event); err != nil {
				e.safeReport(err, event.GetEventType())
				e.CountErroredEvent(event.GetEventType())
			}

			e.recordQueued()
		}
		close(e.done)
	}()
}

func (e *Emitter) countEvent(action string, eventType string) {
	if e.stats == nil {
		return
	}

	tags := statter.Tags{
		"action":     action,
		"event_type": eventType,
	}

	ctx := context.Background()
	e.stats.Counter(ctx, "event", tags, 1)
}

// CountErroredEvent counts an errored event.
func (e *Emitter) CountErroredEvent(eventType string) {
	e.countEvent("errored", eventType)
}

func (e *Emitter) safeReport(err error, eventType string) {
	// safeReport might be called after the logger is closed. If it is,
	// catch the resulting panic and just log it. :(
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Error reporting %q! %#v", err.Error(), r)
		}
	}()

	ctx := context.Background()
	e.log.Report(ctx, err, kvp.String("messaging.hydro.event.type", eventType))
	e.log.Error(ctx, "Error emitting hydro event", kvp.Err(err), kvp.String("messaging.hydro.event.type", eventType))
}

// EmitQueueRun publishes a message for a queue run call.
func (e *Emitter) EmitQueueRun(queueRunResult *hydroV0.QueueRun) {
	if !launchconfig.EmitQueueRunEvent() {
		return
	}

	e.Emit(NewHydroEvent(QueueRunEvent, queueRunResult))
}

// EmitWorkflowExecution publishes a message for workflow execution
func (e *Emitter) EmitWorkflowExecution(execution *hydroV0.WorkflowExecution) {
	// used by CodeScanning on GHES
	e.Emit(NewHydroEvent(WorkflowExecutionEvent, execution))
}

// EmitJobExecution publishes a message for the job execution
func (e *Emitter) EmitJobExecution(execution *hydroV0.JobExecution) {
	// used for Server Statistics on GHES
	e.Emit(NewHydroEvent(JobExecutionEvent, execution))
}

// EmitWorkflowCancelRequest publishes a message for workflow execution
func (e *Emitter) EmitWorkflowCancelRequest(evt *hydroV0.WorkflowCancelRequest) {
	if !launchconfig.EmitWorkflowCancelRequestEvent() {
		return
	}

	e.Emit(NewHydroEvent(WorkflowCancelRequest, evt))
}

func (e *Emitter) EmitWorkflowUpdateEvent(ctx context.Context, evt *hydroV0.WorkflowUpdate) error {
	if !launchconfig.EmitWorkflowUpdateEvent() {
		return nil
	}

	return e.EmitBlockingWithPartitionKey(ctx, NewHydroEvent(WorkflowUpdate, evt), evt.WorkflowRunId)
}

func (e *Emitter) recordQueued() {
	e.stats.Gauge(context.Background(), metrickeys.HydroEventsQueued, nil, int64(len(e.events)))
}
