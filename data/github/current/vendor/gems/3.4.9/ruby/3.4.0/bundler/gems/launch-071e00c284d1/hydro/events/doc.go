// Package events provides some helpers for interacting with hydro.
//
// Here's how you probably want to use this:
//
//	emitter, _ := events.NewEmitter(events.WithKafkaPublisher(...))
//	// make sure that async events are finished sending.
//	defer emitter.Close()
//	...
//	// report an event asynchronously.
//	emitter.Emit(myevent)
//
// In test, you can create a no-op dispatcher like this:
//
//	emitter := events.NewEmitter(events.WithNullPublisher())
package events
