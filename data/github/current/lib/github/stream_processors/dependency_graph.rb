# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependencyGraph
      autoload :DependabotEventProcessor, "github/stream_processors/dependency_graph/dependabot_event_processor"
      autoload :SnapshotProcessedProcessor, "github/stream_processors/dependency_graph/snapshot_processed_processor"
    end
  end
end
