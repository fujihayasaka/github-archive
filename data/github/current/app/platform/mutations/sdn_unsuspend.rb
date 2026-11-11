# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SdnUnsuspend < Platform::Mutations::Base
      BATCH_SIZE = 100

      visibility :internal, environments: [:dotcom]
      description "Unsuspend an actor in compliance with SDN (specially designated nationals) protocols."

      minimum_accepted_scopes ["site_admin"]

      argument :actor_mappings, [Inputs::SdnActorMapping, null: false], "A list of actor (user, organization, or enterprise) mappings to unsuspend.", required: true, visibility: :internal
      argument :reason, String, "The reason for unsuspending the actor", required: true

      field :unsuspended_actors,
        Connections.define(Unions::SdnSuspendable),
        "The unsuspended actors",
        connection: true,
        numeric_pagination_enabled: true,
        null: true
      error_fields

      def resolve(**inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to remove SDN suspension."
        end

        errors = []
        unsuspended_actors = []
        actor_mappings = inputs[:actor_mappings]
        actor_mappings.each_slice(BATCH_SIZE) do |batch|
          actors = Promise.all(batch.map do |actor_mapping|
            Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Organization, Objects::Enterprise], actor_mapping.actor_id, context)
          end).sync

          actors.each do |actor|
            if (actor.is_a?(Business) && !actor.suspended?) || (!actor.is_a?(Business) && !actor.sdn_suspended?)
              errors << {
                message: "Actor #{actor.id} is not SDN suspended.",
              }
              next
            end

            success = if actor.is_a?(Business)
              actor.unsuspend(inputs[:reason], actor: context[:viewer], sdn_suspension: true)
            else
              actor.sdn_unsuspend(staff_user: context[:viewer], reason: inputs[:reason])
            end

            if success
              unsuspended_actors << actor
            else
              errors << {
                message: "There was an error while unsuspending the actor #{actor.id}. Contact #trade-compliance for assistance.",
              }
            end
          end
        end

        {
          unsuspended_actors: ArrayWrapper.new(unsuspended_actors),
          errors: errors
        }
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].display_login, permission: "can-execute-trade-controls")
        )
      end
    end
  end
end
