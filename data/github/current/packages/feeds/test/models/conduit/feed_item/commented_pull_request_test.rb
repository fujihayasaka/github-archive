# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CommentedPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor, from_example: :review_comment_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
      @pull_request_comment = create(:issue_comment, issue: @pull_request.issue)
    end

    setup do
      twirp_item = build(:twirp_conduit_pull_request_comment_feed_item, pull_request: @pull_request, comment: @pull_request_comment)
      @feed_item = Conduit::FeedItem::CommentedPullRequest.new(twirp_item, actor: @actor, subject: @pull_request_comment)
    end

    context "#issue_id" do
      test "returns pull_request's issue id" do
        assert_equal @pull_request.issue.id, @feed_item.issue_id
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "commented on a pull request in", @feed_item.action_string
      end
    end

    context "#description" do
      test "returns correct string" do
        assert_equal "#{@actor} commented on a pull request in #{@repo.name}", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "PULL_REQUEST_COMMENTED", @feed_item.analytics_card_type
      end
    end

    context "#resource_type" do
      test "returns PULL_REQUEST_COMMENT" do
        assert_equal "PULL_REQUEST_COMMENT", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the pull_request comment ID" do
        assert_equal @pull_request_comment.id, @feed_item.resource_id
      end
    end

    context "#source" do
      test "returns the repository name with display owner" do
        assert_equal @repo.name_with_display_owner, @feed_item.source
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::CommentedPullRequest.supports_graphql?
      end
    end

    context "#payload" do
      test "includes the correct information" do
        assert_equal @feed_item.payload[:action], :created
        assert_equal @feed_item.payload[:issue][:id], @pull_request.issue.id
        assert_equal @feed_item.payload[:comment][:id], @pull_request_comment.id
      end
    end
  end
end
