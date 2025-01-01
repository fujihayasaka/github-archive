# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::UnassignedIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @assignee = create(:user)
      @repo = create(:repository, owner: @actor, name: "woof")
      @repo.add_member(@assignee)
      @issue = create(:issue, repository: @repo, user: @actor, assignee: @assignee)
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_feed_item, :unassigned, issue: @issue, actor_user: @actor)
      @feed_item = Conduit::FeedItem::UnassignedIssue.new(twirp_item, actor: @actor, subject: @issue)
    end

    context "#issue" do
      test "returns issue" do
        assert_equal @issue, @feed_item.issue
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::UnassignedIssue.supports_graphql?
      end
    end

    context "#payload" do
      test "includes labels" do
        assert_equal @feed_item.payload[:assignee][:id], @assignee.id
        assert_equal @feed_item.payload[:assignees].first[:id], @assignee.id
      end
    end
  end
end
