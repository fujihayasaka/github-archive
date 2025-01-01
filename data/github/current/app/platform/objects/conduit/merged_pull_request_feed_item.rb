# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module Conduit
      class MergedPullRequestFeedItem < Platform::Objects::Base
        description "A feed item representing the act of an open source pull request being merged"

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

        field :actor, Objects::User, "The author of the pull request", null: false

        field :pull_request, Objects::PullRequest, "The pull request that was merged", null: false, method: :subject
      end
    end
  end
end
