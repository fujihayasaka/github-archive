# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependencyGraph
      class SnapshotProcessedProcessor < SingleMessageProcessor
        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependency_graph-snapshot_processed_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.dependencygraph\.v1\.SnapshotProcessed\Z/

        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Processes an individual SnapshotProcessed message from Hydro.
        #
        # This processor handles the unified SnapshotProcessed event emitted by ds-api
        # for both Dependabot and external snapshots.
        #
        # @param message - An individual GitHub::StreamProcessors::Message representing a Hydro event.
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          repository_id = message.value[:repository_id]
          sha = message.value[:sha]
          snapshot_id = message.value[:snapshot_id]
          ref = message.value[:ref]
          detector_name = message.value[:detector_name]
          correlator = message.value[:correlator]
          scanned_at = Time.at(message.value.dig(:scanned_at, :seconds))
          created_at = Time.at(message.value.dig(:created_at, :seconds))
          snapshot_type = message.value[:snapshot_type]

          GitHub.logger.info(
            "SnapshotProcessedProcessor processing event",
            repository_id: repository_id,
            snapshot_type: snapshot_type,
          )

          DependencySnapshotCompletedJob.perform_later(
            repository_id,
            sha,
            snapshot_id: snapshot_id,
            ref: ref,
            detector_name: detector_name,
            correlator: correlator,
            scanned_at: scanned_at,
            created_at: created_at,
            snapshot_type: snapshot_type
          )
        end
      end
    end
  end
end
