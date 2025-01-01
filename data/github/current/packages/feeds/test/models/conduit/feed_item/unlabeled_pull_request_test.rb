# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::UnlabeledPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @label = create(:label, repository: @repo)
      @pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @actor, labels: [@label])
    end

    setup do
      twirp_item = build(:twirp_conduit_pull_request_feed_item,
        action: Conduit::TwirpHelper.unlabeled_action,
        pull_request: @pull_request,
        actor_user: @actor)
      @feed_item = Conduit::FeedItem::UnlabeledPullRequest.new(twirp_item, actor: @actor, subject: @pull_request)
    end

    context "#pull_request" do
      test "returns pull_request" do
        assert_equal @pull_request, @feed_item.pull_request
      end
    end

    context "#payload" do
      test "returns labels in the payload" do
        assert_equal @feed_item.payload[:labels].first[:id], @label.id
        assert_equal @feed_item.payload[:label][:id], @label.id
      end
    end
  end
end
