# typed: true
# frozen_string_literal: true

module Conduit
  class Web::Renderer
    FEED_ITEM_COMPONENTS = {
      Conduit::FeedItem::AddedToList               => ::Feed::Cards::AddedToListComponent,
      Conduit::FeedItem::CreatedDiscussion         => ::Feed::Cards::DiscussionComponent,
      Conduit::FeedItem::CreatedFeedPost           => ::Feed::Cards::FeedPostComponent,
      Conduit::FeedItem::CreatedRepository         => ::Feed::Cards::CreatedRepositoryComponent,
      Conduit::FeedItem::FollowRecommendation      => ::Feed::Cards::FollowRecommendationComponent,
      Conduit::FeedItem::FollowedUser              => ::Feed::Cards::FollowedUserComponent,
      Conduit::FeedItem::ForkedRepository          => ::Feed::Cards::ForkedRepositoryComponent,
      Conduit::FeedItem::MergedPullRequest         => ::Feed::Cards::MergedPullRequestComponent,
      Conduit::FeedItem::NearSponsorsGoal          => ::Feed::Cards::NearSponsorsGoalComponent,
      Conduit::FeedItem::PublishedRelease          => ::Feed::Cards::ReleaseComponent,
      Conduit::FeedItem::RepositoryRecommendation  => ::Feed::Cards::RepositoryRecommendationComponent,
      Conduit::FeedItem::SponsorableUser           => ::Feed::Cards::NewlySponsorableComponent,
      Conduit::FeedItem::SponsoredUser             => ::Feed::Cards::SponsoredUserComponent,
      Conduit::FeedItem::StarredRepository         => ::Feed::Cards::StarredRepositoryComponent,
      Conduit::FeedItem::TrendingRepository        => ::Feed::Cards::TrendingRepoComponent,
      Conduit::FeedItem::PrivateToPublicRepository => ::Feed::Cards::PrivateToPublicRepositoryComponent,
      Conduit::FeedItem::LabeledIssue              => ::Feed::Cards::LabeledIssueComponent,
      Conduit::FeedItem::LabeledPullRequest        => ::Feed::Cards::LabeledPullRequestComponent,
    }.freeze

    FEED_ITEM_NEXT_COMPONENTS = {
      Conduit::FeedItem::FollowedUser              => ::Feed::Cards::FollowedUserNextComponent,
      Conduit::FeedItem::PublishedRelease          => ::Feed::Cards::ReleaseNextComponent,
      Conduit::FeedItem::SponsoredUser             => ::Feed::Cards::SponsoredUserNextComponent,
      Conduit::FeedItem::NearSponsorsGoal          => ::Feed::Cards::NearSponsorsGoalNextComponent,
      Conduit::FeedItem::SponsorableUser           => ::Feed::Cards::NewlySponsorableNextComponent,
      Conduit::FeedItem::ForkedRepository          => ::Feed::Cards::ForkedRepositoryNextComponent,
      Conduit::FeedItem::StarredRepository         => ::Feed::Cards::StarredRepositoryNextComponent,
      Conduit::FeedItem::AddedToList               => ::Feed::Cards::AddedToListNextComponent,
      Conduit::FeedItem::PrivateToPublicRepository => ::Feed::Cards::PrivateToPublicRepositoryNextComponent,
      Conduit::FeedItem::CreatedRepository         => ::Feed::Cards::CreatedRepositoryNextComponent,
      Conduit::FeedItem::LabeledIssue              => ::Feed::Cards::LabeledIssueNextComponent,
      Conduit::FeedItem::MergedPullRequest         => ::Feed::Cards::MergedPullRequestNextComponent,
      Conduit::FeedItem::LabeledPullRequest        => ::Feed::Cards::LabeledPullRequestNextComponent,
      Conduit::FeedItem::CreatedDiscussion         => ::Feed::Cards::DiscussionNextComponent,
      Conduit::FeedItem::FollowRecommendation      => ::Feed::Cards::FollowRecommendationNextComponent,
      Conduit::FeedItem::RepositoryRecommendation  => ::Feed::Cards::RepositoryRecommendationNextComponent,
      Conduit::FeedItem::TrendingRepository        => ::Feed::Cards::TrendingRepoNextComponent,
      Conduit::FeedItem::ClosedPullRequest         => ::Feed::Cards::ClosedPullRequestNextComponent,
      Conduit::FeedItem::CreatedIssue              => ::Feed::Cards::CreatedIssueNextComponent,
      Conduit::FeedItem::CreatedPullRequest        => ::Feed::Cards::CreatedPullRequestNextComponent,
      Conduit::FeedItem::ClosedIssue               => ::Feed::Cards::ClosedIssueNextComponent,
      Conduit::FeedItem::ReopenedIssue             => ::Feed::Cards::ReopenedIssueNextComponent,
      Conduit::FeedItem::ReopenedPullRequest       => ::Feed::Cards::ReopenedPullRequestNextComponent,
      Conduit::FeedItem::MemberAddToRepository     => ::Feed::Cards::MemberAddToRepositoryNextComponent,
      Conduit::FeedItem::CommentedPullRequest      => ::Feed::Cards::CommentedPullRequestNextComponent,
      Conduit::FeedItem::CommentedIssue            => ::Feed::Cards::CommentedIssueNextComponent,
      Conduit::FeedItem::PushEvent                 => ::Feed::Cards::PushEventComponent,
      Conduit::FeedItem::CreatePush                => ::Feed::Cards::CreatePushComponent,
      Conduit::FeedItem::DeletePush                => ::Feed::Cards::DeletePushComponent,
    }

    attr_reader :item

    def initialize(item:, exp_context: nil, viewer: nil)
      @item = item
      @exp_context = exp_context
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
      @component ||= begin
        if item.rollup? && item.show_related_items?
          return preview_component
        end

        if item.announcement? && sticky_announcements_enabled?
          ::Feed::PinnedAnnouncementsContainerComponent
        else
          preview_component
        end
      end
    end

    def tags
      ["component:#{stats}"]
    end

    private

    attr_reader :exp_context, :viewer

    def sticky_announcements_enabled?
      exp_context&.sticky_announcements_enabled?
    end

    def renderer_class_name
      component.name.demodulize.gsub("Component", "").underscore
    end

    def preview_component
      redesigned_component = FEED_ITEM_NEXT_COMPONENTS[item.class]

      if redesigned_component.present?
        redesigned_component
      else
        FEED_ITEM_COMPONENTS[item.class]
      end
    end
  end
end
