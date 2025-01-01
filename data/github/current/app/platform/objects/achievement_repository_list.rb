# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AchievementRepositoryList < Platform::Objects::Base
      description "A list sampling the Repositories that qualify a user for an Achievement."

      mobile_only true

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :repositories, Connections.define(Objects::Repository), null: false,
        description: "Highlighted repositories that qualify the viewer for an Achievement."

      def repositories
        ArrayWrapper.new(object.repositories)
      end
    end
  end
end
