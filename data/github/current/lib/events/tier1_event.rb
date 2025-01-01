# typed: true
# frozen_string_literal: true

module Events
  # Events::Tier1Event represents a protobuf Tier 1 Event message and provides serialization into the hash format
  # expected by the Ruby protobuf client.
  #
  # See https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/events_platform/v0/tier1_event.proto
  #
  # Note that the GUID can be passed to the Tier1Event. This can be used during the roll out of Events V2
  # to ensure the GUID is consistent between the Tier 1 events and the pre-existing Events V1 events.
  class Tier1Event
    sig { returns(Symbol) }
    attr_reader :type

    sig { returns(Symbol) }
    attr_reader :action

    sig { returns(Events::Entity) }
    attr_reader :actor

    sig { returns(Events::Metadata) }
    attr_accessor :metadata

    sig { returns(T.nilable(Time)) }
    attr_accessor :triggered_at

    sig { returns(T.nilable(String)) }
    attr_accessor :guid

    sig { returns(T.nilable(Events::Target)) }
    attr_reader :target

    sig { returns(T.nilable(Integer)) }
    attr_reader :target_repository_id

    sig { returns(T.nilable(Integer)) }
    attr_reader :target_organization_id

    sig { returns(T.nilable(Integer)) }
    attr_accessor :target_business_id

    sig { returns(T.nilable(Events::EventAttachment)) }
    attr_accessor :event_attachment

    sig { returns(T.nilable(Events::DerivedFlags)) }
    attr_accessor :flags

    sig do
      params(
        type: Symbol,
        action: Symbol,
        actor: Events::Entity,
        metadata: Events::Metadata,
        triggered_at: T.nilable(Time),
        guid: T.nilable(String),
        target: T.nilable(Events::Target),
        target_repository_id: T.nilable(Integer),
        target_organization_id: T.nilable(Integer),
        target_business_id: T.nilable(Integer),
        event_attachment: T.nilable(Events::EventAttachment),
        flags: T.nilable(Events::DerivedFlags)
      ).void
    end
    def initialize(
      type:,
      action:,
      actor:,
      metadata:,
      triggered_at: nil,
      guid: nil,
      target: nil,
      target_repository_id: nil,
      target_organization_id: nil,
      target_business_id: nil,
      event_attachment: nil,
      flags: nil
    )
      @type = type
      @action = action
      @triggered_at = triggered_at
      @actor = actor
      @metadata = metadata
      @guid = guid
      @target = target
      @target_repository_id = target_repository_id
      @target_organization_id = target_organization_id
      @target_business_id = target_business_id
      @event_attachment = event_attachment
      @flags = flags
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      triggered_at_timestamp = Google::Protobuf::Timestamp.new(seconds: @triggered_at.to_i) if @triggered_at
      {
        type: @type,
        action: @action,
        triggered_at: triggered_at_timestamp,
        actor: @actor.to_h,
        metadata: @metadata.to_h,
        guid: @guid,
        target: @target&.to_h,
        target_repository_id: @target_repository_id,
        target_organization_id: @target_organization_id,
        target_business_id: @target_business_id,
        event_attachment: @event_attachment&.to_h,
        flags: @flags&.to_h
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.type == self.type &&
        other.action == self.action &&
        other.triggered_at == self.triggered_at &&
        other.actor == self.actor &&
        other.metadata == self.metadata &&
        other.guid == self.guid &&
        other.target == self.target &&
        other.target_repository_id == self.target_repository_id &&
        other.target_organization_id == self.target_organization_id &&
        other.target_business_id == self.target_business_id &&
        other.event_attachment == self.event_attachment &&
        other.flags == self.flags
    end
  end

  # Metadata represents the metadata field in a Tier1Event message and contains fields common to all events.
  class Metadata
    sig { returns(T.nilable(String)) }
    attr_accessor :github_request_id

    sig { returns(T.nilable(String)) }
    attr_accessor :otel_trace_id

    sig { returns(T::Boolean) }
    attr_reader :disabled_for_import

    sig { returns(T.nilable(T::Array[TrackedWrite])) }
    attr_accessor :tracked_writes

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :spammy_user_acting_outside_own_repos

    sig { params(disabled_for_import: T::Boolean, spammy_user_acting_outside_own_repos: T.nilable(T::Boolean), github_request_id: T.nilable(String), otel_trace_id: T.nilable(String), tracked_writes: T.nilable(T::Array[TrackedWrite])).void }
    def initialize(
      disabled_for_import:,
      spammy_user_acting_outside_own_repos: false,
      github_request_id: nil,
      otel_trace_id: nil,
      tracked_writes: nil
    )
      @github_request_id = github_request_id
      @otel_trace_id = otel_trace_id
      @disabled_for_import = disabled_for_import
      @tracked_writes = tracked_writes
      @spammy_user_acting_outside_own_repos = spammy_user_acting_outside_own_repos ? true : false
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        github_request_id: @github_request_id,
        otel_trace_id: @otel_trace_id,
        disabled_for_import: @disabled_for_import,
        tracked_writes: @tracked_writes&.map { |write| write.to_h },
        spammy_user_acting_outside_own_repos: @spammy_user_acting_outside_own_repos
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.github_request_id == self.github_request_id &&
        other.otel_trace_id == self.otel_trace_id &&
        other.disabled_for_import == self.disabled_for_import &&
        other.tracked_writes == self.tracked_writes && other.spammy_user_acting_outside_own_repos == self.spammy_user_acting_outside_own_repos
    end
  end

  # Entity represents a single entity the Tier 1 event either acts upon or is related to. These are normally
  # model classes in the database, but may be other elements.
  class Entity
    sig { returns(Symbol) }
    attr_reader :type

    sig { returns(String) }
    attr_reader :id

    sig { returns(T.nilable(String)) }
    attr_reader :graphql_global_relay_id

    sig { returns(T.nilable(String)) }
    attr_reader :graphql_next_global_id

    sig { params(type: Symbol, id: String, graphql_global_relay_id: T.nilable(String), graphql_next_global_id: T.nilable(String)).void }
    def initialize(
      type:,
      id:,
      graphql_global_relay_id: nil,
      graphql_next_global_id: nil
    )
      @type = type
      @id = id
      @graphql_global_relay_id = graphql_global_relay_id
      @graphql_next_global_id = graphql_next_global_id
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        type: @type,
        id: @id,
        graphql_global_relay_id: @graphql_global_relay_id,
        graphql_next_global_id: @graphql_global_relay_id
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.type == self.type &&
        other.id == self.id &&
        other.graphql_global_relay_id == self.graphql_global_relay_id &&
        other.graphql_next_global_id == self.graphql_next_global_id
    end
  end

  # Target holds the primary entity that the event acts upon and any related entities.
  class Target
    sig { returns(Events::Entity) }
    attr_reader :primary_entity

    sig { returns(T::Array[Events::Entity]) }
    attr_reader :related_entities

    sig { params(primary_entity: Events::Entity, related_entities: T::Array[Events::Entity]).void }
    def initialize(
      primary_entity:,
      related_entities:)
      @primary_entity = primary_entity
      @related_entities = related_entities
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        primary_entity: @primary_entity.to_h,
        related_entities: @related_entities.map { |entity| entity.to_h }
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.primary_entity == self.primary_entity &&
        other.related_entities == self.related_entities
    end
  end

  # TrackedWrite represents a the last write information for a database cluster. This is set automatically
  # as part of the Events::Tier1EventPublisher.
  class TrackedWrite
    sig { returns(T.nilable(String)) }
    attr_reader :gtid

    sig { returns(Symbol) }
    attr_reader :cluster_name

    # Time is expected to be in milliseconds.
    sig { returns(T.nilable(Integer)) }
    attr_reader :time

    # Time is expected to be in milliseconds.
    sig { params(cluster_name: Symbol, gtid: T.nilable(String), time: T.nilable(Integer)).void }
    def initialize(
      cluster_name:,
      gtid: nil,
      time: nil)
      @gtid = gtid
      @cluster_name = cluster_name
      @time = time
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      time_seconds = @time.to_i / 1000
      {
        gtid: @gtid,
        cluster_name: @cluster_name.to_s,
        time: Google::Protobuf::Timestamp.new(seconds: time_seconds, nanos: @time.to_i - (time_seconds * 1000))
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.gtid == self.gtid &&
        other.cluster_name == self.cluster_name &&
        other.time == self.time
    end
  end

  class EventAttachment
    sig { returns(String) }
    attr_reader :type_url

    sig { returns(String) }
    attr_reader :message

    sig { params(type_url: String, message: String).void }
    def initialize(type_url:, message:)
      @type_url = type_url
      @message = message
    end

    def to_h
      {
        type_url: @type_url,
        message: @message
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.type_url == self.type_url &&
        other.message == self.message
    end
  end

  ## DerivedFlags are flags that are set based on feature flag values in the monolith. They are primarily used
  # during the rollout of events.
  class DerivedFlags
    sig { returns(Events::WebhookFlags) }
    attr_reader :webhook_flags

    sig { params(webhook_flags: Events::WebhookFlags).void }
    def initialize(webhook_flags:)
      @webhook_flags = webhook_flags
    end

    def to_h
      {
        webhook_flags: @webhook_flags.to_h
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.webhook_flags == self.webhook_flags
    end
  end

  ## WebhookFlags are derived flags that are set based on feature flag values in the monolith. They are primarily used
  # during the rollout of events. These flags are specifically for webhooks.
  class WebhookFlags
    sig { returns(T::Boolean) }
    attr_reader :webhook_deliveries_enabled

    sig { returns(T::Boolean) }
    attr_reader :events_v2_validation_enabled

    sig { params(webhook_deliveries_enabled: T::Boolean, events_v2_validation_enabled: T::Boolean).void }
    def initialize(webhook_deliveries_enabled:, events_v2_validation_enabled:)
      @webhook_deliveries_enabled = webhook_deliveries_enabled
      @events_v2_validation_enabled = events_v2_validation_enabled
    end

    def to_h
      {
        webhook_deliveries_enabled: @webhook_deliveries_enabled,
        events_v2_validation_enabled: @events_v2_validation_enabled
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.webhook_deliveries_enabled == self.webhook_deliveries_enabled &&
        other.events_v2_validation_enabled == self.events_v2_validation_enabled
    end
  end
end
