# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::AssignedPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @assignee = create(:user)
      @repo = create(:repository, owner: @actor)
      @repo.add_member(@assignee)
      @pull_request = create(
        :pull_request,
        :disable_disk_access,
        user: @actor,
        repository: @repo,
        assignees: [@assignee]
      )
    end

    setup do
      @twirp_item = build(
        :twirp_conduit_pull_request_feed_item,
        :assigned,
        pull_request: @pull_request,
        actor_user: @actor
      )
      @feed_item = Conduit::FeedItem::AssignedPullRequest.new(
        @twirp_item,
        actor: @actor,
        subject: @pull_request,
      )
    end

    context "#payload" do
      test "returns payload with assignee information" do
        assert_equal @feed_item.payload[:assignee][:id], @assignee.id
        assert_equal @feed_item.payload[:assignees].first[:id], @assignee.id
      end
    end
  end
end
