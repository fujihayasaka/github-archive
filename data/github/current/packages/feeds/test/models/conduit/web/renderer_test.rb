# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class Web::RendererTest < GitHub::TestCase
    include FeedTestHelpers

    setup do
      @viewer = build(:user)
      @exp_context = Conduit::ExpContext.new(@viewer)
    end

    context "CreatedDiscussion event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:discussion_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::DiscussionComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:discussion_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::DiscussionNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:discussion_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "discussion_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:discussion_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "discussion_next_item_component"
      end
    end

    context "MergedPullRequest event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::MergedPullRequestComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::MergedPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "merged_pull_request_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "merged_pull_request_next_item_component"
      end
    end

    context "CreatedPullRequest event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::CreatedPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "created_pull_request_next_item_component"
      end
    end

    context "ReopenedPullRequest event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :reopened)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ReopenedPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :reopened)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "reopened_pull_request_next_item_component"
      end
    end

    context "ClosedPullRequest event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :closed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ClosedPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :closed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "closed_pull_request_next_item_component"
      end
    end

    context "CommentedPullRequest event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_comment_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::CommentedPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_comment_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "commented_pull_request_next_item_component"
      end
    end

    context "SponsoredUser event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsored)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::SponsoredUserComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsored)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::SponsoredUserNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsored)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "sponsored_user_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsored)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.stats, "sponsored_user_next_item_component"
      end
    end

    context "FollowedUser event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :followed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::FollowedUserComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :followed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer, exp_context: @exp_context)

        assert_equal renderer.component, ::Feed::Cards::FollowedUserNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :followed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "followed_user_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :followed)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "followed_user_next_item_component"
      end
    end

    context "SponsorableUser event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsorable)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::NewlySponsorableComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsorable)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::NewlySponsorableNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsorable)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "newly_sponsorable_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :sponsorable)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "newly_sponsorable_next_item_component"
      end
    end

    context "PublishedRelease event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:release_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ReleaseComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:release_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ReleaseNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:release_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "release_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:release_feed_item)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.stats, "release_next_item_component"
      end
    end

    context "CreatedRepository event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::CreatedRepositoryComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::CreatedRepositoryNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "created_repository_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "created_repository_next_item_component"
      end
    end

    context "RepositoryRecommendation event", skip_if_feature_enabled: :turn_off_jazz_user_repository_recommendations do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :recommended)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::RepositoryRecommendationNextComponent
        assert_equal renderer.item, item
      end

      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :recommended)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::RepositoryRecommendationComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :recommended)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "repository_recommendation_next_item_component"
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :recommended)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "repository_recommendation_item_component"
      end
    end

    context "ForkedRepository event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :forked)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ForkedRepositoryComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :forked)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ForkedRepositoryNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :forked)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "forked_repository_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :forked)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "forked_repository_next_item_component"
      end
    end

    context "StarredRepository event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :starred)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::StarredRepositoryComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :starred)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::StarredRepositoryNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :starred)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "starred_repository_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:repository_feed_item, :starred)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "starred_repository_next_item_component"
      end
    end

    context "AddedToList event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_list_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::AddedToListComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_list_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::AddedToListNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_list_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "added_to_list_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_list_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "added_to_list_next_item_component"
      end
    end

    context "NearSponsorsGoal event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :near_sponsors_goal)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::NearSponsorsGoalComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :near_sponsors_goal)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::NearSponsorsGoalNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :near_sponsors_goal)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "near_sponsors_goal_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :near_sponsors_goal)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "near_sponsors_goal_next_item_component"
      end
    end

    context "FollowRecommendation event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :follow_recommendation)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::FollowRecommendationNextComponent
        assert_equal renderer.item, item
      end

      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :follow_recommendation)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::FollowRecommendationComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :follow_recommendation)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "follow_recommendation_next_item_component"
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:user_feed_item, :follow_recommendation)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "follow_recommendation_item_component"
      end
    end

    context "CreatedFeedPost event" do
      test "#component" do
        item = build(:feed_post_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::FeedPostComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        item = build(:feed_post_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "feed_post_item_component"
      end
    end

    context "TrendingRepository event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:trending_repository_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::TrendingRepoNextComponent
        assert_equal renderer.item, item
      end

      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:trending_repository_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::InlineTrendingRepositoriesContainerComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:trending_repository_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "trending_repo_next_item_component"
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:trending_repository_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "inline_trending_repositories_container_item_component"
      end
    end

    context "LabeledIssue event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::LabeledIssueComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::LabeledIssueNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "labeled_issue_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "labeled_issue_next_item_component"
      end
    end

    context "LabeledPullRequest event" do
      test "#component" do
        disable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :labeled)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::LabeledPullRequestComponent
        assert_equal renderer.item, item
      end

      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :labeled)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::LabeledPullRequestNextComponent
        assert_equal renderer.item, item
      end

      test "#stats" do
        disable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :labeled)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "labeled_pull_request_item_component"
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:pull_request_feed_item, :labeled)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "labeled_pull_request_next_item_component"
      end
    end

    context "CreatedIssue event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.component, ::Feed::Cards::CreatedIssueNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :created)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.stats, "created_issue_next_item_component"
      end
    end

    context "ClosedIssue event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :closed)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.component, ::Feed::Cards::ClosedIssueNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :closed)
        renderer = Conduit::Web::Renderer.new(item:)

        assert_equal renderer.stats, "closed_issue_next_item_component"
      end
    end

    context "ReopenedIssue event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :reopened)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::ReopenedIssueNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_feed_item, :reopened)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "reopened_issue_next_item_component"
      end
    end

    context "CommentedIssue event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_comment_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::CommentedIssueNextComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:issue_comment_feed_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "commented_issue_next_item_component"
      end
    end

    context "Push event" do
      test "#redesigned component" do
        enable_feature_flag(:feeds_v2)
        item = build(:push_event_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.component, ::Feed::Cards::PushEventComponent
        assert_equal renderer.item, item
      end

      test "#redesigned stats" do
        enable_feature_flag(:feeds_v2)
        item = build(:push_event_item)
        renderer = Conduit::Web::Renderer.new(item:, viewer: @viewer)

        assert_equal renderer.stats, "push_event_item_component"
      end
    end
  end
end
