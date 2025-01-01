# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::LabeledIssueTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof")
      @label = create(:label, name: "help wanted", repository: @repo)
      @issue = create(:issue, repository: @repo, user: @actor)
    end

    setup do
      twirp_item = build(:twirp_conduit_issue_feed_item, issue: @issue, actor_user: @actor)
      @feed_item = Conduit::FeedItem::LabeledIssue.new(twirp_item, actor: @actor, subject: @issue)
      @issue.labels = [@label]
    end

    context "#issue" do
      test "returns issue" do
        assert_equal @issue, @feed_item.issue
      end
    end

    context "action_string" do
      test "returns correct string" do
        assert_equal "labeled an issue", @feed_item.action_string
      end
    end

    context "#description" do
      test "returns correct string" do
        assert_equal "doggo labeled an issue help wanted in woof", @feed_item.description
      end

      test "returns most recent label when there are multiple labels" do
        new_label = create(:label, name: "good first issue", repository: @repo)
        @issue.labels = [@label, new_label]

        assert_equal "doggo labeled an issue good first issue in woof", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "returns correct string" do
        assert_equal "LABELED_ISSUE", @feed_item.analytics_card_type
      end
    end

    context "#resource_type" do
      test "returns ISSUE" do
        assert_equal "ISSUE", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the issue ID" do
        assert_equal @issue.id, @feed_item.resource_id
      end
    end

    context "#source" do
      test "returns the repository name with display owner" do
        assert_equal @repo.name_with_display_owner, @feed_item.source
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::LabeledIssue.supports_graphql?
      end
    end
  end
end
