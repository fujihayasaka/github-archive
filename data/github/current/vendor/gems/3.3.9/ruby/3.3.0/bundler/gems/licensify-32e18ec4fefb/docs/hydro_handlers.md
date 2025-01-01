# Hydro Handlers

Licensify uses Hydro handlers that react to events (typically emitted from Dotcom) that
effect how licenses are consumed for a given Customer.

These are the main building blocks that power Licensify. Our aim is to operate as
transparently as possible by plugging into existing system events rather than creating
new ones.

## Creating a new handler

1. Implement a new handler in `internal/hydro/handlers/<your_handler_name>_handler.go`
2. Define a new `const` in `internal/hydro/topics/topics.go`. The name of the const
  should follow the pattern `<TopicName>Topic`. The value of the const should be
  the schema URL that points to the event definition.
3. Add the new topic & handler into the `internal/hydro/eventhandlers/eventhandlers.go`
  as a part of the `switch` block on `topic` in the `HandleRaw` function.
