# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedPostTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @verified_user = create(:verified_user)
    @unverified_user = create(:user)
    @spammy_user = create(:spammy_user, :verified)
    @org = create(:organization)
  end

  test "requires a body" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:feed_post, body: "")
    end

    assert_includes error.message, "Body is too short"
  end

  if GitHub.email_verification_enabled?
    test "author has verified email" do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post, author: @unverified_user, owner: @unverified_user)
      end
      assert_includes error.message, "must have a verified email"
    end
  end

  if GitHub.spamminess_check_enabled?
    test "author is not spammy" do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post, author: @spammy_user, owner: @spammy_user)
      end
      assert_includes error.message, "cannot create a post at this time"
    end

    test "owner is not spammy" do
      spammy_org = create(:organization, :spammy)
      spammy_org.add_member(@verified_user)
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post, author: @verified_user, owner: spammy_org)
      end
      assert_includes error.message, "cannot create a post at this time"
    end
  end

  context "scopes" do
    test "owned_by return posts owned by the user" do
      @org.add_admin(@verified_user)

      owned_post = create(:feed_post, author: @verified_user, owner: @verified_user)
      _authored_post = create(:feed_post, author: @verified_user, owner: @org)

      assert_equal [owned_post], FeedPost.owned_by(@verified_user).to_a
    end

    test "authored_by returns posts authored by the user" do
      @org.add_admin(@verified_user)

      owned_post = create(:feed_post, author: @verified_user, owner: @verified_user)
      authored_post = create(:feed_post, author: @verified_user, owner: @org)

      assert_same_elements [owned_post, authored_post], FeedPost.authored_by(@verified_user).to_a
    end
  end

  context "#author_can_post_for_owner" do
    test "true if author is owner" do
      post = create(:feed_post, author: @verified_user, owner: @verified_user)
      assert_predicate post, :valid?
    end

    test "false if author is not owner and both are users" do
      owner = create(:user)
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post, author: @verified_user, owner: owner)
      end
      assert_includes error.message, "can't create a post as #{owner.login}"
    end

    test "true if posting as the admin of an org" do
      @org.add_admin(@verified_user)

      post = create(:feed_post, author: @verified_user, owner: @org)
      assert_predicate post, :valid?
    end

    test "true if posting as a member of an org" do
      org = create(:organization)
      org.add_member(@verified_user)

      error = assert_raises(ActiveRecord::RecordInvalid) do
        create(:feed_post, author: @verified_user, owner: org)
      end
      assert_includes error.message, "can't create a post as #{org.login}"
    end
  end

  context ".create_with_references" do
    test "creates with references" do
      Conduit::Client.any_instance.stubs(:create_feed_post_event).returns(nil)
      author = create(:user, :verified)
      mention = create(:user)
      params = { body: "@#{mention.login}", author_id: author.id, owner_id: author.id }

      post = FeedPost.create_with_references(params)

      assert_predicate post, :persisted?
      assert_equal 1, post.feed_post_references.count
      assert_equal [mention], post.user_mentions
    end

    test "nil when record invalid" do
      params = { body: "Hello, world", author_id: 234, owner_id: 1234 }
      assert_nil FeedPost.create_with_references(params)
    end

    test "nil when conduit api call fails" do
      Conduit::Client.any_instance.stubs(:create_feed_post_event).raises(Conduit::Client::Error.new("this is bad"))
      author = create(:user, :verified)
      mention = create(:user)
      params = { body: "@#{mention.login}", author_id: author.id, owner_id: author.id }

      assert_nil FeedPost.create_with_references(params)
    end
  end

  context "#deletable_by?" do
    test "true if actor is author" do
      @org.add_admin(@verified_user)
      post = create(:feed_post, author: @verified_user, owner: @org)
      assert post.deletable_by?(@verified_user)
    end

    test "true if actor is owner" do
      @org.add_admin(@verified_user)
      post = create(:feed_post, author: @verified_user, owner: @org)
      assert post.deletable_by?(@org)
    end

    test "false if actor is not author or owner" do
      post = create(:feed_post)
      refute post.deletable_by?(@verified_user)
    end
  end

  context "destroy" do
    test "on conduit success" do
      Conduit::Client.any_instance.stubs(:delete_feed_post_event).returns(nil)
      feed_post = create(:feed_post)
      assert_equal feed_post.destroy, feed_post
    end

    test "on conduit error" do
      Conduit::Client.any_instance.stubs(:delete_feed_post_event).raises(Conduit::Client::Error.new)
      feed_post = create(:feed_post)
      assert_nil feed_post.destroy
      assert_equal feed_post.destroyed?, false
    end
  end

  context "destroy!" do
    test "raises" do
      feed_post_id = 123
      feed_post = create(:feed_post, id: feed_post_id)
      err = assert_raises(FeedPost::MethodNotSupported) do
        feed_post.destroy!
      end
      assert_includes err.message, "FeedPost#destroy! is not supported. Use FeedPost#destroy instead"
      assert_equal FeedPost.exists?(feed_post_id), true
    end
  end

  context "delete" do
    test "raises" do
      feed_post_id = 123
      feed_post = create(:feed_post, id: feed_post_id)
      err = assert_raises(FeedPost::MethodNotSupported) do
        feed_post.delete
      end
      assert_includes err.message, "FeedPost#delete is not supported. Use FeedPost#destroy instead"
      assert_equal FeedPost.exists?(feed_post_id), true
    end
  end

  context "Hydro events" do
    test "on create" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

      feed_post = create(:feed_post)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post: Hydro::EntitySerializer.feed_post(feed_post),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(feed_post.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_CREATE,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPost")
      assert_hydro_messages(count: 1, schema: "hydro.schemas.github.feeds.v0.UserPost")
    end

    test "on update" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

      feed_post = create(:feed_post)
      feed_post.update!(body: "new body")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post: Hydro::EntitySerializer.feed_post(feed_post),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(feed_post.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_UPDATE,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPost")
      assert_hydro_messages(count: 2, schema: "hydro.schemas.github.feeds.v0.UserPost")
    end

    test "on delete" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
      Conduit::Client.any_instance.stubs(:delete_feed_post_event).returns(nil)

      feed_post = create(:feed_post)
      feed_post.destroy

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user_post: Hydro::EntitySerializer.feed_post(feed_post),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        specimen_body: Hydro::EntitySerializer.specimen_data(feed_post.body),
        method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_DELETE,
      }

      assert_hydro_published(message, schema: "hydro.schemas.github.feeds.v0.UserPost")
      assert_hydro_messages(count: 2, schema: "hydro.schemas.github.feeds.v0.UserPost")
    end
  end

  context "rate limits" do
    test "returns false when rate limit is exceeded" do
      user = create(:user, :verified)
      enable_content_creation_rate_limiting
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              create(:feed_post, author: user)
            end
            post = build(:feed_post, author: user)

            refute post.save
            assert_equal expected_errors, post.errors.full_messages
          end
        end
      end
    end
  end

end
