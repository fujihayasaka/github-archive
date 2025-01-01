# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveStar < Platform::Mutations::Base
      description "Removes a star from a Starrable."

      minimum_accepted_scopes %w[public_repo gist]

      argument :starrable_id, ID, "The Starrable ID to unstar.", required: true, loads: Interfaces::Starrable
      argument :starrable_context, String,
        "The context in which the object was unstarred, e.g., the page the button was on.",
        required: false, visibility: :internal

      field :starrable, Interfaces::Starrable, "The starrable.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, starrable:, **inputs)
        case starrable
        when ::Repository
          permission.async_owner_if_org(starrable).then do |org|
            permission.access_allowed?(:unstar, resource: starrable, current_repo: starrable, current_org: org, allow_integrations: false, allow_user_via_granular_actor: true)
          end
        when ::Gist
          starrable.async_user.then do |owner|
            org = owner.is_a?(::Organization) ? owner : nil
            permission.access_allowed?(:unstar_gist, resource: starrable, current_org: org, current_repo: nil,  allow_integrations: false, allow_user_via_granular_actor: true)
          end
        when ::Topic
          permission.access_allowed?(
            :public_site_information,
            resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        else
          raise Platform::Errors::Internal, "Unexpected subject type: #{starrable.class}. Only repositories and gists can be starred."
        end
      end

      def resolve(starrable:, starrable_context: nil)
        context[:viewer].unstar(starrable, context: starrable_context)

        { starrable: starrable }
      end
    end
  end
end
