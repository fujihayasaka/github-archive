# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module Conduit
      class SponsoredUserFeedItem < Platform::Objects::Base
        description "A feed item representing the act of an entity being sponsored"

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
        mobile_only true

        implements Interfaces::FeedItemDisplayable

        # Both users and organizations can be sponsored
        field :sponsorable, Unions::SponsorableItem, "The subject that was sponsored", null: false, method: :subject

        # Both users and organizations can sponsor
        field :sponsor, Unions::Sponsor, "The actor who performed the sponsor action", null: false, method: :actor

        # Only users can follow
        field :display_subject, Unions::SponsorableItem, "The user to display instead of sponsorable", null: false, visibility: :internal
      end
    end
  end
end
