# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class FeedPost < Platform::Objects::Base
      description "A feed post"

      # Authorization checks for feed items happen in Conduit. Running additional auth checks
      # is redundant and should be avoided. It can be assumed that any item that made it this
      # far should be visible to the viewer.
      #
      # https://github.com/github/conduit/blob/master/internal/feedauthz/authz.go#L98-L109
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      field :author, Objects::User, "The user who authored the post", null: false
      field :owner, Objects::User, "The user who owns the post", null: false
      field :comments, Connections.define(Objects::FeedPostComment), "The replies to this post", null: false

      def comments
        ArrayWrapper.new([])
      end
    end
  end
end
