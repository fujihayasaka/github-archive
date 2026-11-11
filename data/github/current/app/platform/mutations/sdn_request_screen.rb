# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SdnRequestScreen < Platform::Mutations::Base
      BATCH_SIZE = 100

      visibility :internal, environments: [:dotcom]
      description "Request a screening of an actor in compliance with SDN (Specially Designated Nationals) protocols, irrespective of prior checks."

      minimum_accepted_scopes ["site_admin"]

      argument :actor_mappings, [Inputs::SdnActorMapping, null: false], "A list of actors (user, organization, or enterprise) to screen.", required: true, visibility: :internal

      field :screened_actors,
        Connections.define(Unions::SdnSuspendable),
        "The screened actors",
        connection: true,
        numeric_pagination_enabled: true,
        null: true
      error_fields

      def resolve(**inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to SDN screen actors."
        end

        errors = []
        screened_actors = []
        actor_mappings = inputs[:actor_mappings]
        actor_mappings.each_slice(BATCH_SIZE) do |batch|
          actors = Promise.all(batch.map do |actor_mapping|
            Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Organization, Objects::Enterprise], actor_mapping.actor_id, context)
          end).sync

          actors.each do |actor|
            unless actor.has_saved_trade_screening_record?
              errors << {
                message: "Actor #{actor.id} doesn't have a valid trade screening record.",
              }
              next
            end

            actor.perform_live_sdn_screening(force: true)
            screened_actors << actor
          end
        end

        {
          screened_actors: ArrayWrapper.new(screened_actors),
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
