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
        type_defn.field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true
        type_defn.created_at_field
      end

      add_fields(self)
      def self.included(child_class)
        add_fields(child_class)
      end

      database_id_field(visibility: :internal)
      full_database_id_field(visibility: :internal)

      def actor
        return @object.async_actor unless @object.respond_to?(:async_event_actor)

        @object.async_event_actor(viewer: @context[:viewer])
      end

      field :safe_actor, Interfaces::Actor, "Identifies the actor who performed the event, fallback to ghost", null: true, visibility: :internal
      def safe_actor
        @object.async_actor.then do |actor|
          next actor || User.ghost unless @object.respond_to?(:async_event_actor)

          @object.async_event_actor(viewer: @context[:viewer], actor: actor).then do |event_actor|
            event_actor || User.ghost
          end
        end
      end
    end
  end
end
