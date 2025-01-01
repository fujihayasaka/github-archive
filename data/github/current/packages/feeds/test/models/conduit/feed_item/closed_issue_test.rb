# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::ClosedIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @issue = create(:issue, repository: @repo, user: @actor)
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_feed_item, :closed, issue: @issue, actor_user: @actor)
      @feed_item = Conduit::FeedItem::ClosedIssue.new(twirp_item, actor: @actor, subject: @issue)
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "closed an issue", @feed_item.action_string
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "ISSUE_CLOSED", @feed_item.analytics_card_type
      end
    end

    context "#payload" do
      test "includes the correct action" do
        assert_equal @feed_item.payload[:action], :closed
      end
    end
  end
end
