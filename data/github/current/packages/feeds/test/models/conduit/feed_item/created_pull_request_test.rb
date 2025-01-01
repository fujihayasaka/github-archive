# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CreatedPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @pr = create(:pull_request, :disable_disk_access, repository: @repo)
    end

    setup do
      @twirp_item = build(
        :twirp_conduit_pull_request_feed_item,
        :created,
        pull_request: @pr,
        actor_user: @actor
      )
      @actor = @pr.user
      @feed_item = Conduit::FeedItem::CreatedPullRequest.new(
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
        assert_equal "opened a pull request", @feed_item.action_string
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "CREATED_PULL_REQUEST", @feed_item.analytics_card_type
      end
    end

    context "#payload" do
      test "returns the correct action" do
        assert_equal @feed_item.payload[:action], :opened
      end
    end
  end
end
