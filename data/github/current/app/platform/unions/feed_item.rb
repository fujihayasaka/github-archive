# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class FeedItem < Platform::Unions::Base
      description "Types that can appear in the dashboard feed"
      mobile_only true

      possible_types(
        Objects::Conduit::StarredRepositoryFeedItem,
        Objects::Conduit::ForkedRepositoryFeedItem,
        Objects::Conduit::CreatedRepositoryFeedItem,
        Objects::Conduit::PublishedReleaseFeedItem,
        Objects::Conduit::CreatedDiscussionFeedItem,
        Objects::Conduit::SponsoredUserFeedItem,
        Objects::Conduit::FollowedUserFeedItem,
        Objects::Conduit::BecameSponsorableFeedItem,
        Objects::Conduit::RepositoryRecommendationFeedItem,
        Objects::Conduit::AddedToListFeedItem,
        Objects::Conduit::NearSponsorsGoalFeedItem,
        Objects::Conduit::FollowRecommendationFeedItem,
        Objects::Conduit::MergedPullRequestFeedItem,
        Objects::Conduit::MemberAddToRepositoryFeedItem,
      )

      def self.resolve_type(object, context)
        object.class.const_get(:GRAPHQL_TYPE)
      end
    end
  end
end
