# frozen_string_literal: true

module Ingest
  class SnapshotRequestProcessor < Processor
    def initialize(name: "snapshot_request", debug: false)
      super
    end

    def consume_message(message)
      DependencyGraph.logger.info("SnapshotRequestProcessor#consume_message ran a no-op")
    end

    # Used by `script/etl/tail_snapshot_requests`
    # Print just enough to debug, not enough to potentially expose PII.
    def consume_debug_message(message)
      debug_message = {
        partition: message.partition,
        offset: message.offset,
        repository_id: message.value.dig(:repository, :id),
        manifest_files_count: message.value[:manifest_files].try(:count),
      }
      puts debug_message
    end
  end
end
