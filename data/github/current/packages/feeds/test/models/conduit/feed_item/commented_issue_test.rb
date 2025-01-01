# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CommentedIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @issue = create(:issue, repository: @repo, user: @actor)
      @issue_comment = create(:issue_comment, issue: @issue)
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_comment_feed_item, issue: @issue, comment: @issue_comment)
      @feed_item = Conduit::FeedItem::CommentedIssue.new(twirp_item, actor: @actor, subject: @issue_comment)
    end

    context "#issue_id" do
      test "returns issue id" do
        assert_equal @issue.id, @feed_item.issue_id
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "commented on an issue in", @feed_item.action_string
      end
    end

    context "#description" do
      test "returns correct string" do
        assert_equal "#{@actor} commented on an issue in #{@repo.name}", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "ISSUE_COMMENTED", @feed_item.analytics_card_type
      end
    end

    context "#resource_type" do
      test "returns ISSUE_COMMENT" do
        assert_equal "ISSUE_COMMENT", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the issue comment ID" do
        assert_equal @issue_comment.id, @feed_item.resource_id
      end
    end

    context "#source" do
      test "returns the repository name with display owner" do
        assert_equal @repo.name_with_display_owner, @feed_item.source
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::CommentedIssue.supports_graphql?
      end
    end

    context "#payload" do
      test "includes the correct information" do
        assert_equal @feed_item.payload[:action], :created
        assert_equal @feed_item.payload[:issue][:id], @issue.id
        assert_equal @feed_item.payload[:comment][:id], @issue_comment.id
      end
    end
  end
end
