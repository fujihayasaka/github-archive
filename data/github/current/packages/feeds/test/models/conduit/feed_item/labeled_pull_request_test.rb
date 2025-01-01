# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::LabeledPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof")
      @label = create(:label, name: "help wanted", repository: @repo)
      @pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @actor, labels: [@label])
    end

    setup do
      twirp_item = build(:twirp_conduit_pull_request_feed_item,
        action: Conduit::TwirpHelper.labeled_action,
        pull_request: @pull_request,
        actor_user: @actor)
      @feed_item = Conduit::FeedItem::LabeledPullRequest.new(twirp_item, actor: @actor, subject: @pull_request)
    end

    context "#pull_request" do
      test "returns pull_request" do
        assert_equal @pull_request, @feed_item.pull_request
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "labeled a pull request", @feed_item.action_string
      end
    end

    context "#description" do
      test "returns correct string" do
        assert_equal "doggo labeled a pull request help wanted in woof", @feed_item.description
      end

      test "returns most recent label when there are multiple labels" do
        new_label = create(:label, name: "good first issue", repository: @repo)
        @pull_request.labels << new_label

        assert_equal "doggo labeled a pull request good first issue in woof", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "LABELED_PULL_REQUEST", @feed_item.analytics_card_type
      end
    end

    context "#resource_type" do
      test "returns PULL_REQUEST" do
        assert_equal "PULL_REQUEST", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the pull_request ID" do
        assert_equal @pull_request.id, @feed_item.resource_id
      end
    end

    context "#source" do
      test "returns the repository name with display owner" do
        assert_equal @repo.name_with_display_owner, @feed_item.source
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::LabeledPullRequest.supports_graphql?
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
