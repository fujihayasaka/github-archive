# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

# This client provides methods to check the current 'readiness' of Dependabot-generated snapshot data.
#
# TODO(brrygrdn): Address race condition around 'no event' outcomes
#
# - Currently `DEPENDABOT_READINESS_REASON_NO_EVENT` will return as ready:true to avoid blocking if
#   DS-API has not stored an event to avoid blocking alert processing if no Parse Once ecosystems are involved.
# - This requires us to ensure that DS-API has had time to analyse changes, determine an event is needed
#   and store it before this check is called which will result in a race condition.
# - We need to eliminate this race condition by either:
#   - a/ Having DS-API trigger the alerting process synchronously once it has completed writing events to disk
#   - b/ Having DS-API always write an event to disk even if Parse Once is not involved so we can evaluate no event
#        has ready: false
#
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
