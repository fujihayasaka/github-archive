# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::RequestedReviewPullRequestTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof", from_example: :review_comment_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
    end

    setup do
      subject = build(:twirp_conduit_pull_request, pull_request: @pull_request)
      twirp_item = build(
        :twirp_conduit_pull_request_feed_item,
        :requested_review,
        actor_user: @actor
      )
      @feed_item = Conduit::FeedItem::RequestedReviewPullRequest
        .new(twirp_item, actor: @actor, subject: @pull_request)
    end

    context "#payload" do
      test "it adds the right action" do
        assert_equal :requested, @feed_item.payload[:action]
      end

      test "it adds the request team subject" do
        team = create(:team)
        requested_review = build(
          :twirp_conduit_pull_request_requested_review,
          subject_id: team.id,
          subject_type: :SUBJECT_TYPE_TEAM,
        )
        subject = build(
          :twirp_conduit_pull_request,
          pull_request: @pull_request,
          requested_review:,
        )
        twirp_item = build(:twirp_conduit_pull_request_feed_item,
          :requested_review,
          pull_request_subject: subject,
          actor_user: @actor)
        feed_item = Conduit::FeedItem::RequestedReviewPullRequest
          .new(twirp_item, actor: @actor, subject: @pull_request)

        assert_equal feed_item.payload[:requested_team][:id], team.id
      end

      test "it adds the request user subject" do
        requested_review = build(
          :twirp_conduit_pull_request_requested_review,
          subject_id: @actor.id,
          subject_type: :SUBJECT_TYPE_USER,
        )
        subject = build(
          :twirp_conduit_pull_request,
          pull_request: @pull_request,
          requested_review:,
        )
        twirp_item = build(:twirp_conduit_pull_request_feed_item,
          :requested_review,
          pull_request_subject: subject,
          actor_user: @actor)
        feed_item = Conduit::FeedItem::RequestedReviewPullRequest
          .new(twirp_item, actor: @actor, subject: @pull_request)

        assert_equal feed_item.payload[:requested_reviewer][:id], @actor.id
      end

      test "it supports invalid subject types" do
        requested_review = build(
          :twirp_conduit_pull_request_requested_review,
          subject_id: @actor.id,
          subject_type: :SUBJECT_TYPE_INVALID,
        )
        subject = build(
          :twirp_conduit_pull_request,
          pull_request: @pull_request,
          requested_review:,
        )
        twirp_item = build(:twirp_conduit_pull_request_feed_item,
          :requested_review,
          pull_request_subject: subject,
          actor_user: @actor)
        feed_item = Conduit::FeedItem::RequestedReviewPullRequest
          .new(twirp_item, actor: @actor, subject: @pull_request)

        assert_nil feed_item.payload[:requested_reviewer]
      end
    end
  end
end
