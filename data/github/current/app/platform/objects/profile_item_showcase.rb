# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProfileItemShowcase < Platform::Objects::Base
      description "A curatable list of repositories relating to a repository owner, which defaults to showing the most popular repositories they own."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repository_showcase)
        # A repo showcase only includes public repositories.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # A repo showcase only includes public repositories.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :has_pinned_items, Boolean, method: :has_pinned_items?,
        description: "Whether or not the owner has pinned any repositories or gists.", null: false

      field :items, Connections.define(Unions::PinnableItem),
        description: "The repositories and gists in the showcase. If the profile owner has any pinned items, those will be returned. Otherwise, the profile owner's popular repositories will be returned.",
        null: false

      def items
        ArrayWrapper.new(@object.items)
      end
    end
  end
end
