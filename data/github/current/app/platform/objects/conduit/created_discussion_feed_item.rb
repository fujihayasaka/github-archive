# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module Conduit
      class CreatedDiscussionFeedItem < Platform::Objects::Base
        description "A feed item representing the act of a discussion being created"

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

        implements Interfaces::FeedItemDisplayable

        field :actor, Objects::User, "The user who created the discussion", null: false

        field :discussion, Objects::Discussion, "The discussion that was created", null: false, method: :subject

        field :preview_image_url, Scalars::URI, "The URL of the preview image for this item", null: true

        def preview_image_url
          @object.async_preview_image_url(viewer: context[:viewer])
        end
      end
    end
  end
end
