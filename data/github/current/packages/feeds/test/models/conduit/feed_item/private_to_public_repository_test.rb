# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::PrivateToPublicRepositoryTest < GitHub::TestCase
    fixtures do
      @repository = create(:repository)
    end

    setup do
      @twirp_item = build(
        :twirp_conduit_repository_feed_item,
        repository: @repository,
        action: Conduit::TwirpHelper.published_action
      )
      @feed_item = Conduit::FeedItem::PrivateToPublicRepository.new(
        @twirp_item,
        actor: @repository.owner,
        subject: @repository
      )
    end

    context "#action_string" do
      test "is correct" do
        assert_equal "made this repository public", @feed_item.action_string
      end
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "PRIVATE_TO_PUBLIC_REPOSITORY", @feed_item.analytics_card_type
      end
    end

    context "#reason" do
      test "returns relationship" do
        assert_equal "followed", @feed_item.reason
      end
    end

    context "#made_public_at" do
      test "returns relationship" do
        assert_equal @repository.made_public_at, @feed_item.made_public_at
      end
    end

    context "description" do
      test "is correct" do
        actor = @feed_item.actor
        assert_equal "#{actor.display_login} made this repository public", @feed_item.description
      end
    end
  end
end
