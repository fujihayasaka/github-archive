# typed: true
# frozen_string_literal: true

require "actions_data_stream"
require "global_instrumenter"

ActionsDataStream::EventForwarder.attach!(event_source: GlobalInstrumenter, subscription_keys: ActionsDataStream::ACTIONS)
