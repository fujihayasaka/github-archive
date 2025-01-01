# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::MergedPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @pr = create(:pull_request, :merged, :disable_disk_access, repository: @repo)
    end

    setup do
      @twirp_item = build(:twirp_conduit_pull_request_feed_item, pull_request: @pr, actor_user: @actor)
      @actor = @pr.user
      @feed_item = Conduit::FeedItem::MergedPullRequest.new(
        @twirp_item,
        actor: @actor,
        subject: @pr,
      )
    end

    context "#pull_request" do
      test "returns pr" do
        assert_equal @pr, @feed_item.pull_request
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "contributed to", @feed_item.action_string
      end
    end

    context "#description" do
      test "returns correct string" do
        assert_equal "#{@actor.name} contributed to #{@repo.name}", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "MERGED_PULL_REQUEST", @feed_item.analytics_card_type
      end
    end

    context "#resource_type" do
      test "returns PULL_REQUEST" do
        assert_equal "PULL_REQUEST", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the pr ID" do
        assert_equal @pr.id, @feed_item.resource_id
      end
    end
  end
end
