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
    SCHEMA = "hydro.schemas.events_platform.v0.Tier1Event"

    # Public: Publishes an Events V2 Tier 1 event to Hydro.
    sig { params(event: Events::Tier1Event, topic: String, event_flags: Events::Tier1EventPublisher::EventFlags).void }
    def self.publish(event, topic:, event_flags:)
      return unless event_flags.publish_tier1_events

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

      event.flags = Events::DerivedFlags.new(
        webhook_flags: Events::WebhookFlags.new(
          webhook_deliveries_enabled: event_flags.webhook_deliveries_enabled,
          events_v2_validation_enabled: event_flags.events_v2_validation_enabled
        )
      )

      publisher = GitHub.aqueduct_fallback_hydro_publisher
      event_action = event.action
      event_type = event.type
      start_time = GitHub::Dogstats.monotonic_time
      result = publisher.publish(event.to_h, schema: SCHEMA, topic: topic)

      # Track the attempted publish metric with the result as a string
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("events.tier1_event_publisher.publish_attempt", elapsed, tags: ["topic:#{topic}", "event_type:#{event_type}", "event_action:#{event_action}", "success:#{result}", "enqueued_job:#{publisher.class.name}"])
    end

    # Public: Generates a new GUID for a Tier1 event.
    sig { params(triggered_at: Time).returns(String) }
    def self.new_guid(triggered_at)
      SimpleUUID::UUID.new(triggered_at).to_guid
    end

    # EventFlags encapsulates flags that are used during the rollout of Events V2 that need to be passed both to
    # the legacy event and the Tier 1 event.
    class EventFlags
      attr_reader :webhook_deliveries_enabled, :hookshot_deliveries_enabled, :events_v2_validation_enabled, :publish_tier1_events

      sig { params(webhook_deliveries_enabled: T::Boolean, hookshot_deliveries_enabled: T::Boolean, events_v2_validation_enabled: T::Boolean, publish_tier1_events: T::Boolean).void }
      def initialize(webhook_deliveries_enabled:, hookshot_deliveries_enabled:, events_v2_validation_enabled:, publish_tier1_events:)
        @webhook_deliveries_enabled = webhook_deliveries_enabled
        @hookshot_deliveries_enabled = hookshot_deliveries_enabled
        @events_v2_validation_enabled = events_v2_validation_enabled
        @publish_tier1_events = publish_tier1_events
      end

      def ==(other)
        webhook_deliveries_enabled == other.webhook_deliveries_enabled &&
          hookshot_deliveries_enabled == other.hookshot_deliveries_enabled &&
          events_v2_validation_enabled == other.events_v2_validation_enabled &&
          publish_tier1_events == other.publish_tier1_events
      end

      # Flags that are meant to be passed to the legacy event via active support notification.
      def instrumentation_flags
        {
          hookshot_deliveries_enabled: hookshot_deliveries_enabled,
          events_v2_validation_enabled: events_v2_validation_enabled,
        }
      end
    end

    # Public: Calculate all Events V2 flags for a given event type and action.
    sig { params(event_type: T.nilable(Symbol), event_action: T.nilable(Symbol), target_organization_id: T.nilable(Integer), target_repository_id: T.nilable(Integer)).returns(EventFlags) }
    def self.calculate_event_flags(event_type:, event_action:, target_organization_id:, target_repository_id:)
      # Default values
      webhook_deliveries_enabled = false
      hookshot_deliveries_enabled = true
      validation_enabled = false

      if event_type && FeatureFlag.vexi.enabled?("events_v2_deliveries_enabled", default: false)
        event_type_action = "#{event_type}_#{event_action}"
        events_v2_event_enabled = ff_enabled?(target_organization_id, target_repository_id, "events_v2_#{event_type_action}_enabled")
        events_v2_validation_enabled = ff_enabled?(target_organization_id, target_repository_id, "events_v2_#{event_type_action}_validation_enabled")
        # Determine if the owner of the event is enabled to have Events V2 events delivered. Some events
        # override the ownership check so that we can rollout some events to a wider audience.
        events_v2_owner_enabled = ff_enabled?(target_organization_id, target_repository_id, "events_v2_owner_enabled") ||
            ff_enabled?(target_organization_id, target_repository_id, "events_v2_#{event_type_action}_owner_enabled")
        webhook_deliveries_enabled = events_v2_event_enabled && events_v2_owner_enabled
        # Is this event being delivered from hookshot-go? (This is the default.)
        hookshot_deliveries_enabled = !webhook_deliveries_enabled
        # Are events being validated (double-dispatched) accross both pipelines?
        # If Events V2 deliveries are enabled, we don't want to enable validation for the event since this means
        # hookshot-go would not be delivering the event.
        validation_enabled = !webhook_deliveries_enabled && (events_v2_validation_enabled && events_v2_owner_enabled)
      end

      EventFlags.new(
        # If webhook_deliveries_enabled is true, webhooks will only be delivered through Events V2 via the
        # webhook-deliveries service, they will no longer be delivered via hookshot-go. Internal events sent to
        # Actions and Chat Integrations via internal Aqueduct queues will still be delivered through the legacy
        # pipeline.
        webhook_deliveries_enabled: T.must(webhook_deliveries_enabled),
        # If hookshot_deliveries_enabled is true, webhooks will only be delivered through hookshot-go / Events V1.
        hookshot_deliveries_enabled: hookshot_deliveries_enabled,
        # If events_v2_valdiation_enabled is true, events will be double-dispatched through Events V1 and Events V2,
        # but webhooks will only actually delivered through hookshot-go. This mode is for validating the accuracy of
        # the Events V2 pipeline for a small percentage of events.
        events_v2_validation_enabled: T.must(validation_enabled),
        # If publish_tier1_events is true, Tier 1 event Hydro messages will be published for the event.
        # This should only be the case if webhook_deliveries_enabled is true, or if events_v2_validation_enabled
        # is true.
        publish_tier1_events: T.must(webhook_deliveries_enabled) || T.must(validation_enabled)
      )
    end

    sig { params(organization_id: T.nilable(Integer), repository_id: T.nilable(Integer), ff_name: String).returns(T::Boolean) }
    def self.ff_enabled?(organization_id, repository_id, ff_name)
      org_actor = organization_id ? Events::ParentAsActor.org_actor(organization_id) : nil
      repo_actor = repository_id ? Events::ParentAsActor.repo_actor(repository_id) : nil

      return true if FeatureFlag.vexi.enabled?(ff_name, default: false)
      return true if org_actor&.feature_flag_enabled?(ff_name, default: false) || repo_actor&.feature_flag_enabled?(ff_name, default: false)
      false
    end
    private_class_method :ff_enabled?

  end
end
