# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::UnlabeledIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @label = create(:label, repository: @repo)
      @issue = create(:issue, repository: @repo, user: @actor, labels: [@label])
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_feed_item, :unlabeled, issue: @issue, actor_user: @actor)
      @feed_item = Conduit::FeedItem::UnlabeledIssue.new(twirp_item, actor: @actor, subject: @issue)
    end

    context "#issue" do
      test "returns issue" do
        assert_equal @issue, @feed_item.issue
      end
    end

    context "#payload" do
      test "includes labels" do
        assert_equal @feed_item.payload[:label][:id], @label.id
        assert_equal @feed_item.payload[:labels].first[:id], @label.id
      end
    end
  end
end
