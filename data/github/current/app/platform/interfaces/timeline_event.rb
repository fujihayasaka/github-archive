# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module TimelineEvent
      include Platform::Interfaces::Base
      description "Represents an event on the timeline of an issue or pull request."
      visibility :internal

      global_id_field :id, description: "The Node ID of the TimelineEvent object"

      # TODO add explanatory comment with link
      def self.add_fields(type_defn)
        type_defn.field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true, scope: true
        type_defn.created_at_field
      end

      add_fields(self)
      def self.included(child_class)
        add_fields(child_class)
      end

      database_id_field(visibility: :internal)
      full_database_id_field(visibility: :internal)

      def actor
        async_event_actor
      end

      field :safe_actor, Interfaces::Actor, "Identifies the actor who performed the event, fallback to ghost", null: true, visibility: :internal, scope: true
      def safe_actor
        async_event_actor.then do |actor|
          actor || User.ghost
        end
      end

      private

      def async_event_actor
        return @object.async_actor unless @object.respond_to?(:async_event_actor)

        @object.async_event_actor(viewer: @context[:viewer]).then do |event_actor|
          next event_actor unless FeatureFlag.vexi.enabled?(:refine_timeline_event_actor_gql, @context[:viewer], default: false)

          next event_actor unless event_actor&.bot? && event_actor.respond_to?(:user_programmatic_access)

          event_actor.async_user_programmatic_access.then do |upa|
            upa.async_owner
          end
        end
      end
    end
  end
end
