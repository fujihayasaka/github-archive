# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedPostCommentTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @verified_user = create(:user, :verified)
    @unverified_user = create(:user)
    @spammy_user = create(:spammy_user, :verified)
    @org = create(:organization)
    @spamurai_form_signals = SpamuraiFormSignals.create(request_params: {}).freeze
    @feed_post = create(:feed_post, author: @verified_user, owner: @verified_user)
  end

  setup do
    GitHub.context.push(actor_ip: "3ffe:505:2::1")
    GitHub.context.push(user_agent: "test agent")
    GitHub.context.push(spamurai_form_signals: @spamurai_form_signals)
  end

  test "requires a body" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:feed_post_comment, body: "")
    end

    assert_includes error.message, "Body can't be blank"
  end

  if GitHub.email_verification_enabled?
    test "user has verified email" do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post_comment, user: @unverified_user)
      end
      assert_includes error.message, "must have a verified email"
    end
  end

  if GitHub.spamminess_check_enabled?
    test "user is not spammy" do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post_comment, user: @spammy_user)
      end
      assert_includes error.message, "cannot create a comment at this time"
    end
  end

  test "parent comment belongs to the same post" do
    post = create(:feed_post)
    parent_comment = create(:feed_post_comment, feed_post: post)
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:feed_post_comment, parent_comment: parent_comment, feed_post: create(:feed_post))
    end
    assert_includes error.message, "associated with a different post"
  end

  test "#deleted?" do
    comment = create(:feed_post_comment, deleted_at: Time.now)
    assert_predicate comment, :deleted?
  end

  context "#deletable_by?" do
    test "when actor is user" do
      comment = create(:feed_post_comment)
      assert_equal true, comment.deletable_by?(comment.user)
    end

    test "when actor isn't user" do
      comment = create(:feed_post_comment)
      assert_equal false, comment.deletable_by?(create(:user))
    end
  end

  context "Hydro events" do
    test "on create", skip_enterprise: true do
      comment = create(:feed_post_comment, feed_post: @feed_post)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post_comment: Hydro::EntitySerializer.feed_post_comment(comment),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(@spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_CREATE,
        user_post_id: @feed_post.id,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
      assert_hydro_messages(count: 1, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
    end

    test "on update", skip_enterprise: true do
      comment = create(:feed_post_comment,  body: "old body", feed_post: @feed_post)
      comment.update!(body: "new body")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post_comment: Hydro::EntitySerializer.feed_post_comment(comment),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(@spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_UPDATE,
        user_post_id: @feed_post.id,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
      assert_hydro_messages(count: 2, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
    end

    test "on delete", skip_enterprise: true do
      comment = create(:feed_post_comment, feed_post: @feed_post)
      comment.destroy!

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post_comment: Hydro::EntitySerializer.feed_post_comment(comment),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(@spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_DELETE,
        user_post_id: @feed_post.id,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
      assert_hydro_messages(count: 2, schema: "hydro.schemas.github.feeds.v0.UserPostComment")
    end
  end
end
