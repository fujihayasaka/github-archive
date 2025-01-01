# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class Web::FeedTest < GitHub::TestCase
    include FeedTestHelpers

    fixtures do
      @feed_user = create(:credit_card_user, :sponsorable,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      @sponsorable = create(:credit_card_user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      @sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable)
      @repo = create(:repository, from_example: :tags_galore)
      @release = create(:release,
        name: "v1.0",
        tag_name: "v1.0",
        author: @repo.owner,
        repository: @repo,
        target_commitish: "master"
      )
      @discussion = create(:discussion_with_announcement)
      @issue = create(:issue, repository: @repo, user: @repo.owner)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @repo.owner)
      @pull_request.merge
    end

    setup do
      @feed_filter = Conduit::FeedFilter.new(nil, viewer: @feed_user)
      AzureEXP::AssignmentClient.stubs(:get_assignment).returns(AzureEXP::AssignmentResponse.new(""))
    end

    context "#build_feed_items" do
      test "returns an array of feed items" do
        twirp_items = [
          build(:twirp_conduit_discussion_feed_item, discussion: @discussion),
          build(:twirp_conduit_release_feed_item, release: @release),
          build(:twirp_conduit_repository_feed_item, repository: @repo),
        ]
        feed = build(:conduit_web_feed, twirp_items: twirp_items)

        assert_equal feed.items.count, 3
      end
    end

    context "#reaction_count_by_content_by_discussion_id" do
      test "with feature disabled" do
        Flipper[:disable_discussion_reactions_on_dashboard_feed].disable

        create(:discussion_reaction, discussion: @discussion, content: "smile")
        create(:discussion_reaction, discussion: @discussion, content: "heart")
        create(:discussion_reaction, discussion: @discussion, content: "heart")

        item = build(:twirp_conduit_discussion_feed_item, discussion: @discussion)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_discussion_id
        assert results[@discussion.id]
        assert_equal results[@discussion.id], { "smile" => 1, "heart" => 2 }
      end

      test "with feature enabled" do
        Flipper[:disable_discussion_reactions_on_dashboard_feed].enable

        create(:discussion_reaction, discussion: @discussion, content: "smile")
        create(:discussion_reaction, discussion: @discussion, content: "heart")
        create(:discussion_reaction, discussion: @discussion, content: "heart")

        item = build(:twirp_conduit_discussion_feed_item, discussion: @discussion)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_discussion_id
        assert_nil results
      end
    end

    context "#viewer_reaction_contents_by_discussion_id" do
      test "with feature disabled" do
        Flipper[:disable_discussion_reactions_on_dashboard_feed].disable

        create(:discussion_reaction, discussion: @discussion, content: "smile", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "heart", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "rocket", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "heart")

        item = build(:twirp_conduit_discussion_feed_item, discussion: @discussion)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_discussion_id
        assert results[@discussion.id]
        assert_includes results[@discussion.id], "smile"
        assert_includes results[@discussion.id], "heart"
        assert_includes results[@discussion.id], "rocket"
      end

      test "with feature enabled" do
        Flipper[:disable_discussion_reactions_on_dashboard_feed].enable

        create(:discussion_reaction, discussion: @discussion, content: "smile", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "heart", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "rocket", user: @feed_user)
        create(:discussion_reaction, discussion: @discussion, content: "heart")

        item = build(:twirp_conduit_discussion_feed_item, discussion: @discussion)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_discussion_id
        assert_nil results
      end
    end

    context "#reaction_count_by_content_by_release_id" do
      test "with feature disabled" do
        Flipper[:disable_release_reactions_on_dashboard_feed].disable

        @release.react(actor: @feed_user, content: "smile")
        @release.react(actor: @feed_user, content: "heart")
        @release.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_release_feed_item, release: @release)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_release_id
        assert results[@release.id]
        assert_equal results[@release.id], { "smile" => 1, "heart" => 2 }
      end

      test "with feature enabled" do
        Flipper[:disable_release_reactions_on_dashboard_feed].enable

        @release.react(actor: @feed_user, content: "smile")
        @release.react(actor: @feed_user, content: "heart")
        @release.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_release_feed_item, release: @release)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_release_id
        assert_nil results
      end
    end

    context "#viewer_reaction_contents_by_release_id" do
      test "with feature disabled" do
        Flipper[:disable_release_reactions_on_dashboard_feed].disable

        @release.react(actor: @feed_user, content: "smile")
        @release.react(actor: @feed_user, content: "heart")
        @release.react(actor: @feed_user, content: "rocket")
        @release.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_release_feed_item, release: @release)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_release_id
        assert_includes results[@release.id], "smile"
        assert_includes results[@release.id], "heart"
        assert_includes results[@release.id], "rocket"
      end

      test "with feature enabled" do
        Flipper[:disable_release_reactions_on_dashboard_feed].enable

        @release.react(actor: @feed_user, content: "smile")
        @release.react(actor: @feed_user, content: "heart")
        @release.react(actor: @feed_user, content: "rocket")
        @release.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_release_feed_item, release: @release)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_release_id
        assert_nil results
      end
    end

    context "#reaction_count_by_content_by_pr_issue_id" do
      test "with feature disabled" do
        Flipper[:disable_pull_request_reactions_on_dashboard_feed].disable

        @pull_request.issue.react(actor: @feed_user, content: "smile")
        @pull_request.issue.react(actor: @feed_user, content: "heart")
        @pull_request.issue.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_pull_request_feed_item, pull_request: @pull_request)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_pr_issue_id
        assert results[@pull_request.issue.id]
        assert_equal results[@pull_request.issue.id], { "smile" => 1, "heart" => 2 }
      end

      test "with feature enabled" do
        Flipper[:disable_pull_request_reactions_on_dashboard_feed].enable

        @pull_request.issue.react(actor: @feed_user, content: "smile")
        @pull_request.issue.react(actor: @feed_user, content: "heart")
        @pull_request.issue.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_pull_request_feed_item, pull_request: @pull_request)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.reaction_count_by_content_by_pr_issue_id
        assert_nil results
      end
    end

    context "#viewer_reaction_contents_by_pr_issue_id" do
      test "with feature disabled" do
        Flipper[:disable_pull_request_reactions_on_dashboard_feed].disable

        @pull_request.issue.react(actor: @feed_user, content: "smile")
        @pull_request.issue.react(actor: @feed_user, content: "heart")
        @pull_request.issue.react(actor: @feed_user, content: "rocket")
        @pull_request.issue.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_pull_request_feed_item, pull_request: @pull_request)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_pr_issue_id
        assert_includes results[@pull_request.issue.id], "smile"
        assert_includes results[@pull_request.issue.id], "heart"
        assert_includes results[@pull_request.issue.id], "rocket"
      end

      test "with feature enabled" do
        Flipper[:disable_pull_request_reactions_on_dashboard_feed].enable

        @pull_request.issue.react(actor: @feed_user, content: "smile")
        @pull_request.issue.react(actor: @feed_user, content: "heart")
        @pull_request.issue.react(actor: @feed_user, content: "rocket")
        @pull_request.issue.react(actor: @repo.owner, content: "heart")

        item = build(:twirp_conduit_pull_request_feed_item, pull_request: @pull_request)
        feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

        results = feed.viewer_reaction_contents_by_pr_issue_id
        assert_nil results
      end
    end

    test "#reaction_count_by_content_by_issue_id" do
      @issue.react(actor: @feed_user, content: "smile")
      @issue.react(actor: @feed_user, content: "heart")
      @issue.react(actor: @repo.owner, content: "heart")

      item = build(:twirp_conduit_issue_feed_item, issue: @issue)
      feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

      results = feed.reaction_count_by_content_by_issue_id
      assert results[@issue.id]
      assert_equal results[@issue.id], { "smile" => 1, "heart" => 2 }
    end

    test "#viewer_reaction_contents_by_issue_id" do
      @issue.react(actor: @feed_user, content: "smile")
      @issue.react(actor: @feed_user, content: "heart")
      @issue.react(actor: @feed_user, content: "rocket")
      @issue.react(actor: @repo.owner, content: "heart")

      item = build(:twirp_conduit_issue_feed_item, issue: @issue)
      feed = build(:conduit_web_feed, user: @feed_user, twirp_items: [item])

      results = feed.viewer_reaction_contents_by_issue_id
      assert_includes results[@issue.id], "smile"
      assert_includes results[@issue.id], "heart"
      assert_includes results[@issue.id], "rocket"
    end
  end
end
