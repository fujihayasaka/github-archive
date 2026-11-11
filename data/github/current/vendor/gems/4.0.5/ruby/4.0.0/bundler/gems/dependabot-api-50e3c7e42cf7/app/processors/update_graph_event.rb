# frozen_string_literal: true

class UpdateGraphEvent < ApplicationProcessor
  group_name "update_graph_event"
  handle_topic(/dependency_graph\.v0\.UpdateGraphEvent\Z/, UpdateGraphEventHandler)
end
