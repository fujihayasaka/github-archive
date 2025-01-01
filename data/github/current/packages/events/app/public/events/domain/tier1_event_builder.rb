# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    class Tier1EventBuilder
      class MissingRequiredArgumentError < ArgumentError
        sig { returns(T::Array[Symbol]) }
        attr_reader :missing_fields

        sig { params(missing_fields: T::Array[Symbol]).void }
        def initialize(missing_fields)
          @missing_fields = T.let(missing_fields.to_a, T::Array[Symbol])
          super("Missing required fields: #{missing_fields.join(', ')}")
        end
      end

      sig { void }
      def initialize # rubocop:disable Metrics/MethodLength
        @event_action = T.let(nil, T.nilable(Symbol))
        @event_type = T.let(nil, T.nilable(Symbol))
        @primary_entity_data = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
        @repository = T.let(nil, T.nilable(Repository))
        @actor = T.let(nil, T.nilable(User))
        @check_actor_spammy = T.let(false, T::Boolean)
        @entity_owner = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
        @organization_id = T.let(nil, T.nilable(Integer))
        @business_id = T.let(nil, T.nilable(Integer))
        @attachment_data = T.let(nil, T.nilable(Events::EventAttachment))
        @guid = T.let(nil, T.nilable(String))
        @triggered_at = T.let(nil, T.nilable(Time))
        @related_entities = T.let([], T::Array[Events::Entity])
        @hook_event_attributes = T.let(nil, T.nilable(Events::HookEventAttributes))
        @webhooks_delivery_scope = T.let(nil, T.nilable(Events::WebhooksDeliveryScope))
      end

      sig { params(event_action: Symbol).returns(Tier1EventBuilder) }
      def action(event_action)
        @event_action = event_action
        self
      end

      sig { params(symbol: Symbol).returns(Tier1EventBuilder) }
      def event_type(symbol)
        @event_type = symbol
        self
      end

      sig { params(guid: T.nilable(String)).returns(Tier1EventBuilder) }
      def guid(guid)
        @guid = guid
        self
      end

      sig { params(attributes_attachment: T.untyped).returns(Tier1EventBuilder) }
      def hook_event_attributes(attributes_attachment)
        @hook_event_attributes = Events::HookEventAttributes.new(
          type_url: "type.googleapis.com/#{T.unsafe(attributes_attachment).class.descriptor.name}",
          message: T.unsafe(attributes_attachment).class.encode(attributes_attachment)
        )
        self
      end

      sig { params(hook_id: Integer).returns(Tier1EventBuilder) }
      def single_hook_webhooks_delivery_scope(hook_id)
        @webhooks_delivery_scope = Events::WebhooksDeliveryScope.new(
          hook_scope: Events::HookScope.new(hook_id:)
        )
        self
      end

      sig { params(integration_id: Integer, skip_subscription_check: T::Boolean).returns(Tier1EventBuilder) }
      def single_integration_webhooks_delivery_scope(integration_id, skip_subscription_check = false)
        @webhooks_delivery_scope = Events::WebhooksDeliveryScope.new(
          integration_scope: Events::IntegrationScope.new(integration_id:, skip_subscription_check:)
        )
        self
      end

      sig { params(entity: T.untyped, entity_type: T.nilable(Symbol)).returns(Tier1EventBuilder) }
      def primary_entity(entity, entity_type = nil)
        if entity.present?
          graphql_ids = Events::Domain.domain.graphql_ids(entity)
          @primary_entity_data = {
            entity: entity,
            entity_type: entity_type || :"ENTITY_TYPE_#{entity.class.name.underscore.upcase}",
            graphql_ids: graphql_ids
          }
        end
        self
      end

      sig { params(repository: T.nilable(Repository)).returns(Tier1EventBuilder) }
      def repository(repository) # rubocop:disable Metrics/MethodLength
        if repository.present?
          graphql_ids = Events::Domain.domain.graphql_ids(repository)
          @repository = repository
          @related_entities << Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: repository.id.to_s,
            graphql_global_relay_id: graphql_ids.global_relay_id,
            graphql_next_global_id: graphql_ids.next_global_id
          )
        end
        self
      end

      sig { params(org: T.nilable(Organization)).returns(Tier1EventBuilder) }
      def organization(org)
        if org.present?
          graphql_ids = Events::Domain.domain.graphql_ids(org)
          @organization_id = org.id
          @related_entities << Events::Entity.new(
            type: :ENTITY_TYPE_ORGANIZATION,
            id: org.id.to_s,
            graphql_global_relay_id: graphql_ids.global_relay_id,
            graphql_next_global_id: graphql_ids.next_global_id
          )
        end
        self
      end

      sig { params(business: T.nilable(Business)).returns(Tier1EventBuilder) }
      def business(business)
        if business.present?
          graphql_ids = Events::Domain.domain.graphql_ids(business)
          @business_id = business.id
          @related_entities << Events::Entity.new(
            type: :ENTITY_TYPE_ENTERPRISE,
            id: business.id.to_s,
            graphql_global_relay_id: graphql_ids.global_relay_id,
            graphql_next_global_id: graphql_ids.next_global_id
          )
        end
        self
      end

      sig { params(actor: T.nilable(User), check_spammy: T::Boolean).returns(Tier1EventBuilder) }
      def actor(actor, check_spammy = true)
        if actor.present?
          @actor = actor
          @check_actor_spammy = check_spammy
        end
        self
      end

      sig { params(attachment: Events::EventAttachment).returns(Tier1EventBuilder) }
      def attachment(attachment)
        @attachment_data = attachment
        self
      end

      sig { returns(Events::Tier1Event) }
      def build_tier_1_event
        validate!

        metadata = build_metadata
        actor_entity = build_actor_entity
        primary_entity = build_primary_entity
        target = build_target(primary_entity, @related_entities)

        Events::Tier1Event.new(
          type: T.must(@event_type),
          action: T.must(@event_action),
          target: target,
          actor: actor_entity,
          metadata: metadata,
          hook_event_attributes: @hook_event_attributes,
          webhooks_delivery_scope: @webhooks_delivery_scope,
          target_repository_id: @repository&.id,
          target_organization_id: @organization_id,
          target_business_id: @business_id,
          event_attachment: @attachment_data,
          guid: T.must(@guid),
          triggered_at: @triggered_at
        )
      end

      private

      sig { void }
      def validate!
        fields = []
        fields << :event_type if @event_type.blank?
        fields << :event_action if @event_action.blank?
        fields << :guid if @guid.blank?
        fields << :primary_entity if @primary_entity_data.blank?
        fields

        return if fields.empty?

        raise MissingRequiredArgumentError.new(fields)
      end

      sig { returns(Events::Metadata) }
      def build_metadata
        Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: Events::Domain.domain.model_importing?(@repository),
          spammy_user_acting_outside_own_repos: @check_actor_spammy && @actor.try(:spammy?)
        )
      end

      sig { returns(T.nilable(Events::Entity)) }
      def build_actor_entity
        return unless @actor

        graphql_ids = Events::Domain.domain.graphql_ids(@actor)

        Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @actor.id.to_s,
          graphql_global_relay_id: graphql_ids.global_relay_id,
          graphql_next_global_id: graphql_ids.next_global_id
        )
      end

      sig { returns(Events::Entity) }
      def build_primary_entity
        raise MissingRequiredArgumentError.new([:primary_entity]) if @primary_entity_data.nil?

        Events::Entity.new(
          type: @primary_entity_data[:entity_type],
          id: @primary_entity_data[:entity].id.to_s,
          graphql_global_relay_id: @primary_entity_data[:graphql_ids].global_relay_id,
          graphql_next_global_id: @primary_entity_data[:graphql_ids].next_global_id
        )
      end

      sig { params(primary_entity: Events::Entity, related_entities: T::Array[Events::Entity]).returns(Events::Target) }
      def build_target(primary_entity, related_entities)
        Events::Target.new(
          primary_entity:,
          related_entities:
        )
      end
    end
  end
end
