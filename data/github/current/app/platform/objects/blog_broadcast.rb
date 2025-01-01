# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BlogBroadcast < Platform::Objects::Base
      description "A broadcast blog post."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        GitHub.blog_enabled?
      end

      visibility :internal

      scopeless_tokens_as_minimum

      field :id, Integer, "The post's published timestamp (as Unix time)", null: false
      field :title, String, "The post's title", null: false
      field :url, Scalars::URI, "The post's URL", null: false
      field :content, String, "The post's teaser HTML text", null: false
    end
  end
end
