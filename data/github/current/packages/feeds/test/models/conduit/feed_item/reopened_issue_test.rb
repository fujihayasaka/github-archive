# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::ReopenedIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @issue = create(:issue, repository: @repo, user: @actor)
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_feed_item, :reopened, issue: @issue, actor_user: @actor)
      @feed_item = Conduit::FeedItem::ReopenedIssue.new(twirp_item, actor: @actor, subject: @issue)
    end

    context "#issue" do
      test "returns issue" do
        assert_equal @issue, @feed_item.issue
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "ISSUE_REOPENED", @feed_item.analytics_card_type
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "reopened an issue", @feed_item.action_string
      end
    end

    context "#payload" do
      test "includes the correct action" do
        assert_equal @feed_item.payload[:action], :reopened
      end
    end
  end
end
