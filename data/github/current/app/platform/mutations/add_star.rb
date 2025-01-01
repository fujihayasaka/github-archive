# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddStar < Platform::Mutations::Base
      description "Adds a star to a Starrable."

      minimum_accepted_scopes %w[public_repo gist]

      argument :starrable_id, ID, "The Starrable ID to star.", required: true, loads: Interfaces::Starrable
      argument :starrable_context, String,
        "The context in which the object was starred, e.g., the page the button was on.",
        required: false, visibility: :internal

      field :starrable, Interfaces::Starrable, "The starrable.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, starrable:, **inputs)
        if starrable.is_a?(::Repository)
          permission.async_owner_if_org(starrable).then do |org|
            permission.access_allowed?(:star, resource: starrable, current_repo: starrable, current_org: org, allow_integrations: false, allow_user_via_granular_actor: true)
          end
        elsif starrable.is_a?(::Topic)
          permission.access_allowed?(
            :public_site_information,
            resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        else
          starrable.async_user.then do |owner|
            org = owner.is_a?(::Organization) ? owner : nil
            permission.access_allowed?(:star_gist, resource: starrable, current_org: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(starrable:, starrable_context: nil)
        context[:permission].authorize_content(:star, :create, starrable: starrable)

        case starrable
        when ::Repository
          Stars.domain.star_repository(user: context[:viewer], repository: starrable)
        when ::Topic
          Stars.domain.star_topic(user: context[:viewer], topic: starrable)
        when ::Gist
          Stars.domain.star_gist(user: context[:viewer], gist: starrable)
        end

        { starrable: starrable }
      end
    end
  end
end
