# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module Conduit
      class RepositoryRecommendationFeedItem < Platform::Objects::Base
        description "A feed item representing the act of a repository being recommended"

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

        field :repository, Objects::Repository, "The repository that is recommended", null: false, method: :subject

        field :reason, String, "The reason why the repository was recommended", null: false

        field :gatherer, String, "The gatherer that recommended the repository", null: false, visibility: :internal
      end
    end
  end
end
