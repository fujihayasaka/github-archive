# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

module Events
  # Tier1EventPublisher is responsible for publishing Events V2 Tier 1 Events to Hydro.
  #
  # Tier 1 events should encapsulate enough information for the event to be "hydrated" into a Tier 2 Event
  # if there are any subscribers listening to the event (such as the Webhooks system) that require the fully
  # hydrated payload.
  class Tier1EventPublisher
    extend T::Sig

    # Public: Publishes an Events V2 Tier 1 event to Hydro.
    sig { params(event: Events::Tier1Event, topic: String).void }
    def self.publish(event, topic:)
      target_repo_id = event.target_repository_id
      target_org_id = event.target_organization_id

      return unless (Events::ParentAsActor.org_actor(target_org_id)&.feature_enabled?(:events_v2_publish_tier1_event) ||
                     Events::ParentAsActor.repo_actor(target_repo_id)&.feature_enabled?(:events_v2_publish_tier1_event))

      event.triggered_at = Time.now unless event.triggered_at
      event.guid = new_guid(T.must(event.triggered_at)) unless event.guid

      # For events triggered in GHES we override the provided target_business_id
      event.target_business_id = GitHub.global_business&.id if GitHub.single_business_environment?

      replication_state = DatabaseSelector::ReplicationState.current&.to_hash
      event.metadata.tracked_writes = replication_state&.map do |key, value|
        next unless value.is_a?(Hash)
        TrackedWrite.new(
          gtid: value[:gtid],
          cluster_name: key,
          time: value[:time])
      end

      # Fallback to set otel_trace_id and github_request_id if the call did not set them
      event.metadata.otel_trace_id ||= GitHub.current_span.context.hex_trace_id
      event.metadata.github_request_id ||= GitHub.context[:request_id]

      GitHub.aqueduct_fallback_hydro_publisher.publish(event.to_h, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: topic)
    end

    # Public: Generates a new GUID for a Tier1 event.
    sig { params(triggered_at: Time).returns(String) }
    def self.new_guid(triggered_at)
      SimpleUUID::UUID.new(triggered_at).to_guid
    end
  end
end
