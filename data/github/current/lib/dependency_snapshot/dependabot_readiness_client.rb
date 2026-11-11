# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

# This client provides methods to check the current 'readiness' of Dependabot-generated snapshot data.
module DependencySnapshot
  class DependabotReadinessClient < BaseClient
    def initialize(request_timeout_seconds: 10, connection: nil, use_json: false)
      super
    end

    # Check the overall readiness of snapshot data for a repository based on its most recent event.
    #
    # @param repository_id [Integer] The GitHub repository ID.
    # @param event_type [Symbol] Optionally filter by event type. Defaults to
    #   :DEPENDABOT_EVENT_TYPE_UNSPECIFIED (no filter). Other accepted values:
    #   - :DEPENDABOT_EVENT_TYPE_INIT — Initial repository setup.
    #   - :DEPENDABOT_EVENT_TYPE_PUSH — A push to the repository.
    #
    # @return [Hash] A response containing:
    #   - :ready [Boolean] Whether the repository's snapshot data is ready for processing.
    #   - :reason [Symbol] The reason for the readiness determination. One of:
    #     - :DEPENDABOT_READINESS_REASON_UNSPECIFIED — Default/unknown.
    #     - :DEPENDABOT_READINESS_REASON_NO_EVENT — No event found.
    #     - :DEPENDABOT_READINESS_REASON_PENDING — Some snapshots are still pending within their deadline.
    #     - :DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE — All requested snapshots have been received.
    #     - :DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT — Deadline passed; some snapshots received.
    #     - :DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT — Deadline passed; no snapshots received.
    #   - :most_recent_event [DependabotEvent, nil] The event used to determine readiness, if present. Contains:
    #     - :event_type [Symbol] The type of event (:DEPENDABOT_EVENT_TYPE_INIT, :DEPENDABOT_EVENT_TYPE_PUSH).
    #     - :ref [String] The Git ref associated with the event.
    #     - :sha [String] The commit SHA associated with the event.
    #     - :created_at [Google::Protobuf::Timestamp] The time the event was acknowledged and processing started.
    #
    # @raise [DependencySnapshot::NotFoundError] If the repository is not found.
    # @raise [DependencySnapshot::Error] On unexpected server errors.
    def check_repository_readiness(repository_id:, event_type: :DEPENDABOT_EVENT_TYPE_UNSPECIFIED)
      rpc_request = {
        repository_id: repository_id,
        event_type: event_type,
      }

      rpc("CheckRepositoryReadiness", rpc_request)
    end

    # Check the readiness of snapshot data for a specific Dependabot event by its ID.
    #
    # @param dependabot_event_id [Integer] The Dependabot event ID.
    #
    # @return [Hash] A response containing:
    #   - :ready [Boolean] Whether snapshot data for this event is complete and ready for processing.
    #   - :reason [Symbol] The reason for the readiness determination. One of:
    #     - :DEPENDABOT_READINESS_REASON_UNSPECIFIED — Default/unknown.
    #     - :DEPENDABOT_READINESS_REASON_NO_EVENT — No event found.
    #     - :DEPENDABOT_READINESS_REASON_PENDING — Some snapshots are still pending within their deadline.
    #     - :DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE — All requested snapshots have been received.
    #     - :DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT — Deadline passed; some snapshots received.
    #     - :DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT — Deadline passed; no snapshots received.
    #
    # @raise [DependencySnapshot::NotFoundError] If the event is not found.
    # @raise [DependencySnapshot::Error] On unexpected server errors.
    def check_event_readiness(dependabot_event_id:)
      rpc_request = {
        dependabot_event_id: dependabot_event_id,
      }

      rpc("CheckEventReadiness", rpc_request)
    end

    private

    def twirp_class
      Github::DependencySnapshotsApi::DependabotServiceClient
    end
  end
end
