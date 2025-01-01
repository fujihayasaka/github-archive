# Event Handlers

Event handlers are a generic implementation that wrap the Hydro event processing logic.
The key difference (with some configuration changes & additions) is event handlers
are able to process messages from either Hydro **or** Aqueduct Bridge.

## Creating a new handler

### Hydro messages

Follow the steps in [Hydro Handlers](hydro_handlers.md).

### Aqueduct Bridge messages

1. Implement a new handler in `internal/hydro/eventhandlers/<your_handler_name>_handler.go`.
  Ensure the handle function is a receiver type of the `EventHandler` struct.
2. Add the new handler into the `internal/hydro/eventhandlers/eventhandlers.go`
  as a part of the `switch` block on `message.(type)` in the `HandleRaw` function.
3. Create a new `const` in `internal/aqueduct/queues/queues.go`. The name of the const
  should follow the pattern `<QueueName>Queue`. The value of the const should follow
  the pattern `licensify_<handler_name>`.
4. In [hydro-schemas](https://github.com/github/hydro-schemas), find the topic in
  `bridge-configuration/potomac.yaml` and add a new entry for Licensify. The `app`
  should be `licensify-production` and the `queue` should be the queue value you created in step 3.
5. Repeat step 4 in the `bridge-configuration/proxima.yaml` file.
6. (Optional, development only) In the config/aqueduct_hydro_message_bridge/dotcom.yml file Dotcom, find the topic
  that you want to bridge and add a new entry for Licensify. The `app` should
  be `licensify-<%= Rails.env %>` to match Licensify's Aqueduct app name, and the `queue` should be the name of the queue you created in step 3
  you want to bridge.
