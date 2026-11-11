# typed: true
# frozen_string_literal: true

module Conduit
  class Web::Renderer
    FEED_ITEM_COMPONENTS = {
      Conduit::FeedItem::FollowedUser              => ::Feed::Cards::FollowedUserComponent,
      Conduit::FeedItem::PublishedRelease          => ::Feed::Cards::ReleaseComponent,
      Conduit::FeedItem::SponsoredUser             => ::Feed::Cards::SponsoredUserComponent,
      Conduit::FeedItem::NearSponsorsGoal          => ::Feed::Cards::NearSponsorsGoalComponent,
      Conduit::FeedItem::SponsorableUser           => ::Feed::Cards::NewlySponsorableComponent,
      Conduit::FeedItem::ForkedRepository          => ::Feed::Cards::ForkedRepositoryComponent,
      Conduit::FeedItem::StarredRepository         => ::Feed::Cards::StarredRepositoryComponent,
      Conduit::FeedItem::AddedToList               => ::Feed::Cards::AddedToListComponent,
      Conduit::FeedItem::PrivateToPublicRepository => ::Feed::Cards::PrivateToPublicRepositoryComponent,
      Conduit::FeedItem::CreatedRepository         => ::Feed::Cards::CreatedRepositoryComponent,
      Conduit::FeedItem::LabeledIssue              => ::Feed::Cards::LabeledIssueComponent,
      Conduit::FeedItem::MergedPullRequest         => ::Feed::Cards::MergedPullRequestComponent,
      Conduit::FeedItem::LabeledPullRequest        => ::Feed::Cards::LabeledPullRequestComponent,
      Conduit::FeedItem::CreatedDiscussion         => ::Feed::Cards::DiscussionComponent,
      Conduit::FeedItem::FollowRecommendation      => ::Feed::Cards::FollowRecommendationComponent,
      Conduit::FeedItem::RepositoryRecommendation  => ::Feed::Cards::RepositoryRecommendationComponent,
      Conduit::FeedItem::TrendingRepository        => ::Feed::Cards::TrendingRepoComponent,
      Conduit::FeedItem::ClosedPullRequest         => ::Feed::Cards::ClosedPullRequestComponent,
      Conduit::FeedItem::CreatedIssue              => ::Feed::Cards::CreatedIssueComponent,
      Conduit::FeedItem::CreatedPullRequest        => ::Feed::Cards::CreatedPullRequestComponent,
      Conduit::FeedItem::ClosedIssue               => ::Feed::Cards::ClosedIssueComponent,
      Conduit::FeedItem::ReopenedIssue             => ::Feed::Cards::ReopenedIssueComponent,
      Conduit::FeedItem::ReopenedPullRequest       => ::Feed::Cards::ReopenedPullRequestComponent,
      Conduit::FeedItem::MemberAddToRepository     => ::Feed::Cards::MemberAddToRepositoryComponent,
      Conduit::FeedItem::CommentedPullRequest      => ::Feed::Cards::CommentedPullRequestComponent,
      Conduit::FeedItem::CommentedIssue            => ::Feed::Cards::CommentedIssueComponent,
      Conduit::FeedItem::PushEvent                 => ::Feed::Cards::PushEventComponent,
      Conduit::FeedItem::CreatePush                => ::Feed::Cards::CreatePushComponent,
      Conduit::FeedItem::DeletePush                => ::Feed::Cards::DeletePushComponent,
    }

    attr_reader :item

    def initialize(item:, viewer: nil)
      @item = item
      @viewer = viewer
    end

    def stats
      if item.rollup? && item.show_related_items?
        "#{renderer_class_name}_item_rollup"
      else
        "#{renderer_class_name}_item_component"
      end
    end

    def component
      @component ||= preview_component
    end

    def tags
      ["component:#{stats}"]
    end

    private

    attr_reader :viewer

    def renderer_class_name
      component.name.demodulize.gsub("Component", "").underscore
    end

    def preview_component
      FEED_ITEM_COMPONENTS[item.class]
    end
  end
end
