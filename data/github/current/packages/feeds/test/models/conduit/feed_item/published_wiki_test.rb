# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::PublishedWikiTest < GitHub::TestCase
    fixtures do
      Spokesd.enable_spokesd

      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
    end

    setup do
      @repo.initialize_wiki(@actor)
      @wiki = @repo.unsullied_wiki
      example_repo :wiki, @wiki
      twirp_item = build(:twirp_conduit_wiki_push_feed_item, repo: @repo)
      @subject = {
        repository: @repo,
        updates: [
          {
            action: "published",
            sha: "a" * 40,
            name: "test",
          }.with_indifferent_access
        ]
      }
      @feed_item = Conduit::FeedItem::PublishedWiki.new(twirp_item, actor: @actor, subject: @subject)
    end

    context "#analytics_card_type" do
      test "returns nil" do
        refute @feed_item.analytics_card_type
      end
    end

    context "#api_type" do
      test "returns nil" do
        assert_equal "GollumEvent", @feed_item.api_type
      end
    end

    context "#payload" do
      test "includes page information" do
        assert_equal @feed_item.payload[:pages].count, @subject[:updates].count
        assert_equal "a" * 40, @feed_item.payload[:pages].last[:sha]
        assert_equal "published", @feed_item.payload[:pages].last[:action]
        assert_match "/", @feed_item.payload[:pages].first[:html_url]
      end
    end
  end
end
