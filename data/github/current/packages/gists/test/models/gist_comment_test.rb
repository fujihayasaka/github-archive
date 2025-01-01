# typed: false
# frozen_string_literal: true

require "test_helper"

class GistCommentTest < GitHub::TestCase
  include GistCommentTestHelper
  include StringFromBinaryTestHelper
  ROLES = GitHub::MinimizeComment::ROLES

  fixtures do
    @user = create(:user)
    @comment_user = create(:user)
    @spammer = create(:user)
    @staff = create :staff_admin_user, login: "staffy"
    @gist = GistHelpers.generate \
      contents: gist_test_content_array,
      user: @user,
      created_at: 5.minutes.ago,
      updated_at: 5.minutes.ago
    @comment = create(:gist_comment, gist: @gist, user: @user)
    @staff_user = create(:staff_admin_user)
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "can be commented on" do
    c = nil
    assert_difference("GistComment.count", 1) { c = @gist.comments.create(body: "Lorem to the ipsum", user: @user) }
    assert @user.gist_comments.include?(c)
    assert @gist.comments.include?(c)
  end

  test "gist comments can't be created by a user blocked by the gist author" do
    blocked_user = create(:user)
    @user.block(blocked_user)
    ex = assert_raises(ActiveRecord::RecordInvalid) do
      gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    end
    assert_equal "Validation failed: User is blocked", ex.message
  end

  test "can't comment on gists with comments disabled" do
    enable_feature_flag(:gist_comment_moderation)

    @gist.update!(comments_enabled: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      gist_comment = GistComment.create!(gist: @gist, user: @gist.owner, body: "cool stuff")
    end
    assert_equal "Validation failed: Gist comments are disabled", error.message
  end

  test "can't update comments on gists with comments disabled" do
    enable_feature_flag(:gist_comment_moderation)

    gist_comment = create(:gist_comment, gist: @gist, body: "first content")
    @gist.update!(comments_enabled: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      gist_comment.update!(body: "other content")
    end
    assert_equal "Validation failed: Gist comments are disabled", error.message
    assert_equal "first content", gist_comment.reload.body
  end

  test "can delete comments on gists with comments disabled" do
    enable_feature_flag(:gist_comment_moderation)

    gist_comment = create(:gist_comment, gist: @gist, body: "first content")
    @gist.update!(comments_enabled: false)

    gist_comment.destroy!
    assert_nil GistComment.find_by(id: gist_comment.id)
  end

  test "editing a comment creates gist comment edits" do
    enable_feature_flag(:user_content_edits_double_write)

    # We store two edits, one for the creation and one for the actual edit
    assert_difference -> { GistCommentEdit.count }, 2 do
      @comment.update_body("edited comment body", @user)
    end

    # Every other edit creates one edit record
    assert_difference -> { GistCommentEdit.count }, 1 do
      @comment.update_body("another edit to the comment body", @user)
    end
  end

  test "editing a comment does not create gist comment edits" do
    disable_feature_flag(:user_content_edits_double_write)

    assert_difference -> { GistCommentEdit.count }, 0 do
      @comment.update_body("edited comment body", @user)
    end

    assert_difference -> { GistCommentEdit.count }, 0 do
      @comment.update_body("another edit to the comment body", @user)
    end
  end

  test "gist comments can't be edited by their creator if they are blocked by the gist author" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(blocked_user)
    ex = assert_raises(ActiveRecord::RecordInvalid) do
      gist_comment.update!(body: "it me again")
    end
    assert_equal "Validation failed: User is blocked", ex.message
  end

  test "gist comments created by user who is blocked by the gist author can't be edited by the gist author" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(@user)
    ex = assert_raises(ActiveRecord::RecordInvalid) do
      gist_comment.update!(body: "it me again")
    end
    assert_equal "Validation failed: User is blocked", ex.message
  end

  test "gist comments created by user who is blocked by the gist author can be edited by a site admin" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(@staff)
    gist_comment.update!(body: "it me again")
    assert gist_comment.valid?
  end

  test "gist comments created by user who is blocked by the gist author can be deleted by their creator" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(blocked_user)
    assert_difference("GistComment.count", -1) { gist_comment.destroy }
  end

  test "gist comments created by user who is blocked by the gist author can be deleted by the gist author" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(@user)
    assert_difference("GistComment.count", -1) { gist_comment.destroy }
  end

  test "gist comments created by user who is blocked by the gist author can be deleted by a site admin" do
    blocked_user = create(:user)
    gist_comment = create(:gist_comment, gist: @gist, user: blocked_user)
    @user.block(blocked_user)
    gist_comment.stubs(:modifying_user).returns(@staff)
    assert_difference("GistComment.count", -1) { gist_comment.destroy }
  end

  test "should set target_for_conditional_access correctly " do
    comment_user = create :user
    gist_comment = gist_comment = create(:gist_comment, gist: @gist, user: comment_user)
    anonymous_gist = GitHub.override(:anonymous_gist_creation_enabled, true) do
      create :gist, public: false, user: nil
    end
    anon_gist_comment = create(:gist_comment, gist: anonymous_gist, user: comment_user)

    assert_equal @gist.owner,  gist_comment.target_for_conditional_access
    assert_equal :no_target_for_conditional_access, anon_gist_comment.target_for_conditional_access
  end

  test "should set async_target_for_conditional_access correctly" do
    comment_user = create :user
    gist_comment = gist_comment = create(:gist_comment, gist: @gist, user: comment_user)
    anonymous_gist = GitHub.override(:anonymous_gist_creation_enabled, true) do
      create :gist, public: false, user: nil
    end
    anon_gist_comment = create(:gist_comment, gist: anonymous_gist, user: comment_user)

    assert_equal @gist.owner,  gist_comment.async_target_for_conditional_access.sync
    assert_equal :no_target_for_conditional_access, anon_gist_comment.async_target_for_conditional_access.sync
  end

  unless GitHub.enterprise?
    include HydroTestHelpers

    test "publishes a gist_comment.create event to hydro" do
      gist_comment = create(:gist_comment, gist: @gist)
      first_file = gist_comment.gist.files.first

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(gist_comment.user),
            gist: Hydro::EntitySerializer.gist(gist_comment.gist),
            gist_comment: Hydro::EntitySerializer.gist_comment(gist_comment),
            spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
            specimen_body: Hydro::EntitySerializer.specimen_data(gist_comment.body),
            all_comments_by_gist_author: @gist.all_comments_by_author?,
            specimen_gist_description: Hydro::EntitySerializer.specimen_data(@gist.description),
            specimen_gist_first_path: Hydro::EntitySerializer.specimen_data(first_file.name),
            specimen_gist_content: Hydro::EntitySerializer.specimen_data(first_file.data),
          },
          schema: "github.v1.GistCommentCreate",
        )
      end
    end

    test "GistComment create publishes github.platform_health.v1.UserGeneratedContent" do
      reset_hydro
      gist_comment = create(:gist_comment, gist: @gist)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :CREATE,
        content_type: :GIST_COMMENT,
        actor: Hydro::EntitySerializer.user(gist_comment.user),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.GistCommentCreate"),
        content_database_id: gist_comment.id,
        content_global_relay_id: gist_comment.global_relay_id,
        content_created_at: gist_comment.created_at,
        content_updated_at: gist_comment.updated_at,
        title: nil,
        content: Hydro::EntitySerializer.specimen_data(gist_comment.body),
        parent_content_author: Hydro::EntitySerializer.user(@gist.user),
        parent_content_database_id: @gist.id,
        parent_content_global_relay_id: @gist.global_relay_id,
        parent_content_created_at: @gist.created_at,
        parent_content_updated_at: @gist.updated_at,
        owner: Hydro::EntitySerializer.user(@gist.user),
        repository: nil,
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(gist_comment),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "publishes a gist_comment.update event to hydro" do
      gist_comment = create(:gist_comment, gist: @gist, body: "Old Body")
      gist_comment.update!(body: "New Body")
      first_file = gist_comment.gist.files.first

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(gist_comment.user),
            gist: Hydro::EntitySerializer.gist(gist_comment.gist),
            gist_comment: Hydro::EntitySerializer.gist_comment(gist_comment),
            spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
            current_specimen_body: Hydro::EntitySerializer.specimen_data(gist_comment.body),
            previous_specimen_body: Hydro::EntitySerializer.specimen_data("Old Body"),
            all_comments_by_gist_author: @gist.all_comments_by_author?,
            specimen_gist_description: Hydro::EntitySerializer.specimen_data(@gist.description),
            specimen_gist_first_path: Hydro::EntitySerializer.specimen_data(first_file.name),
            specimen_gist_content: Hydro::EntitySerializer.specimen_data(first_file.data),
          },
          schema: "github.v1.GistCommentUpdate",
        )
      end
    end

    test "GistComment update publishes github.platform_health.v1.UserGeneratedContent" do
      gist_comment = create(:gist_comment, gist: @gist)
      reset_hydro
      gist_comment.update!(body: "New Body")

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :UPDATE,
        content_type: :GIST_COMMENT,
        actor: Hydro::EntitySerializer.user(gist_comment.user),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.GistCommentUpdate"),
        content_database_id: gist_comment.id,
        content_global_relay_id: gist_comment.global_relay_id,
        content_created_at: gist_comment.created_at,
        content_updated_at: gist_comment.updated_at,
        title: nil,
        content: Hydro::EntitySerializer.specimen_data("New Body"),
        parent_content_author: Hydro::EntitySerializer.user(@gist.user),
        parent_content_database_id: @gist.id,
        parent_content_global_relay_id: @gist.global_relay_id,
        parent_content_created_at: @gist.created_at,
        parent_content_updated_at: @gist.updated_at,
        owner: Hydro::EntitySerializer.user(@gist.user),
        repository: nil,
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(gist_comment),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end
  end

  test "bumps gist updated_at on comment" do
    timestamp = @gist.updated_at

    Timecop.freeze(1.day.from_now) do
      @gist.comments.create(body: "Lorem to the ipsum", user: @user)
    end

    refute_equal timestamp, @gist.updated_at
    refute_equal timestamp, @gist.reload.updated_at
  end

  context "when rate limits" do
    test "creation is rate limited per user when rate limiting is enabled" do
      enable_content_creation_rate_limiting
      user = create(:user)
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              @gist.comments.create(body: "Lorem to the ipsum", user: user)
            end

            comment = @gist.comments.new(body: "Lorem to the ipsum", user: user)


            refute comment.save
            assert_equal expected_errors, comment.errors.full_messages
          end
        end
      end
    end

    test "there isn't a rate limit error when rate limiting is disabled" do
      GitHub.stubs(:content_creation_rate_limiting_enabled?).returns(false)
      user = create(:user)
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              @gist.comments.create(body: "Lorem to the ipsum", user: user)
            end

            comment = @gist.comments.new(body: "Lorem to the ipsum", user: user)

            assert_valid comment
            assert comment.save
          end
        end
      end
    end
  end

  context "audit logs" do
    test "instruments gist comment create" do
      events = subscribe "gist_comment.create"
      comment = @gist.comments.create(body: "Hello world", user: @user)

      expected_payload = {
        body: comment.body,
        author: @user.to_s,
        author_id: @user.id,
        gist_comment_id: comment.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments gist comment update" do
      events = subscribe "gist_comment.update"
      comment = @gist.comments.create(body: "Hello world", user: @user)

      comment.update!(body: "New Body")
      expected_payload = {
        body: comment.body,
        old_body: "Hello world",
        author: @user.to_s,
        author_id: @user.id,
        gist_comment_id: comment.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments gist comment destroy" do
      events = subscribe "gist_comment.destroy"
      comment = @gist.comments.create(body: "Hello world", user: @user)

      comment.destroy
      expected_payload = {
        body: comment.body,
        author: @user.to_s,
        author_id: @user.id,
        gist_comment_id: comment.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  test "ensures name is UTF-8 encoded" do
    body = "ümlaut".b
    comment = @gist.comments.create(body: body, user: @user)

    assert_equal Encoding::UTF_8, comment.body.encoding
  end

  test "body is limited to unicode_blob_limit length" do
    # We want to validate on bytelength and return a human readable error
    # message with a pessimistic character limit for MYSQL_UNICODE_BLOB_LIMIT
    expected_bytes = 262144
    expected_characters = expected_bytes / 4
    content = "a" * expected_bytes
    comment = GistComment.new(gist: @gist, user: @user, body: content)
    assert comment.valid?

    comment.body = content + "aa"
    refute comment.valid?
    assert_equal comment.errors[:body][0], "is too long (maximum is #{expected_characters} characters)"
  end

  test "body can contain unicode characters above 0xffff" do
    content = [0x1F514].pack("U")
    comment = @gist.comments.build(body: content, user: @user)
    assert comment.valid?
  end

  if GitHub.spamminess_check_enabled?
    test "gist comment creator can be flagged as spam for naughty content" do
      assert !@user.spammy?, "User is already spammy"

      perform_enqueued_jobs(only: CheckForSpamJob) do
        GitHub::SpamChecker.stubs(:test_comment).returns("totally spammy for sure")
        @gist.comments.create(body: spammy_comment, user: @user)
      end

      assert @user.reload.spammy?
    end
  end

  context "unicode chars" do
    test "4 bytes or more does not invalidate the record." do
      comment = @gist.comments.create(body: "𝄞𝄞𝄞 was here", user: @user)
      assert comment.valid?
    end

    test "3 bytes or less will work too." do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @user)
      assert comment.valid?
    end

    test "body can include recent emoji" do
      encoded_value = "Can I type in a 😍?"
      encoded_value2 = "Can I type in a \xF0\x9F\x98\x8D?"
      comment = @gist.comments.create(body: encoded_value, user: @user)
      assert comment.valid?
      assert_multibyte_tracked_changes(comment, :body, encoded_value, encoded_value2)
    end
  end

  context "determing who can admin a GistComment" do
    test "the comment author can admin" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      assert comment.adminable_by?(@comment_user)
    end

    test "the gist author can admin" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal comment.user, @gist.user
      assert comment.adminable_by?(@gist.user)
    end

    test "a user who isn't the author or staff can't admin" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @spammer
      refute comment.adminable_by?(@spammer)
    end

    test "staff who isn't the author can admin" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @staff
      assert comment.adminable_by?(@staff)
    end

    test "a nil user can't admin" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute comment.adminable_by?(nil)
    end
  end

  context "#async_viewer_can_update?" do
    test "returns true if the given user is the comment author" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      assert comment.async_viewer_can_update?(@comment_user).sync
    end

    test "returns true if the given user is the gist author" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal comment.user, @gist.user
      assert comment.async_viewer_can_update?(@gist.user).sync
    end

    test "returns true if the given user is a staff member" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @staff
      assert comment.async_viewer_can_update?(@staff).sync
    end

    test "returns false for other users" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @spammer
      refute comment.async_viewer_can_update?(@spammer).sync
    end

    test "returns false if the given user is nil" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute comment.async_viewer_can_update?(nil).sync
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)

      assert_equal [], comment.async_viewer_cannot_update_reasons(@comment_user).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(@gist.user).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(@staff).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(@spammer).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync
    end
  end

  context "#async_viewer_can_delete?" do
    test "returns true if the given user is the comment author" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      assert comment.async_viewer_can_delete?(@comment_user).sync
    end

    test "returns true if the given user is the gist author" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal comment.user, @gist.user
      assert comment.async_viewer_can_delete?(@gist.user).sync
    end

    test "returns true if the given user is a staff member" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @staff
      assert comment.async_viewer_can_delete?(@staff).sync
    end

    test "returns false for other users" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute_equal @gist.user, @spammer
      refute comment.async_viewer_can_delete?(@spammer).sync
    end

    test "returns false if the given user is nil" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)
      refute comment.async_viewer_can_delete?(nil).sync
    end
  end

  context "#async_minimizable_by?" do
    test "returns whether the given user can minimize the comment" do
      comment = @gist.comments.create(body: "ÿÿÿ was here", user: @comment_user)

      assert comment.async_minimizable_by?(@gist.user).sync
      assert comment.async_minimizable_by?(@staff).sync
      refute comment.async_minimizable_by?(create(:user)).sync
    end

    test "returns true for comment authored by user" do
      user = create(:user)
      comment = create(:gist_comment, user: user)
      refute comment.gist.adminable_by?(user)
      assert comment.async_minimizable_by?(user).sync
    end

    test "returns false for user who is not gist creator if minimizing other user's comment" do
      comment = create(:gist_comment)
      refute comment.async_minimizable_by?(create(:user)).sync
    end
  end

  context "#comment_path_url" do
    test "uses the /gist prefix in lab environments" do
      GitHub.stubs(:gist3_domain?).returns(false)
      comment = @gist.comments.create(body: "body", user: @comment_user)

      assert_equal comment.comment_path_url, "/gist/#{@user.name}/#{@gist.global_id}/comments/#{comment.id}"
    end

    test "omits the /gist prefix in non-lab environments" do
      GitHub.stubs(:gist3_domain?).returns(true)
      comment = @gist.comments.create(body: "body", user: @comment_user)

      assert_equal comment.comment_path_url, "/#{@user.name}/#{@gist.global_id}/comments/#{comment.id}"
    end
  end

  context "#permalink" do
    test "sets correct url" do
      comment = @gist.comments.create(body: "body", user: @comment_user)

      if GitHub.flipper[:gist_permalink_update].enabled?
        assert_equal comment.permalink, "#{GitHub.gist_url}/#{@gist.user.name}/#{@gist.global_id}#gistcomment-#{comment.id}"
      else
        assert_equal comment.permalink, "#{GitHub.gist_url}/#{@gist.global_id}#gistcomment-#{comment.id}"
      end
    end
  end

  test "allow 64 KB comment" do
    comment = @gist.comments.create(body: "ÿ" * 65535, user: @user)
    assert_predicate comment, :valid?
  end
  test "allow 256 KB comment" do
    comment = @gist.comments.create(body: "a" * 262144, user: @user)
    assert_predicate comment, :valid?
  end
  test "do not allow comment longer than 256 KB" do
    comment = @gist.comments.create(body: "n" * 262145, user: @user)
    refute_predicate comment, :valid?
  end

  context "notifications for GistComments", skip_if_feature_enabled: :notifyd_enable_gist_thread_subscriptions do
    test "notifies subscribers via email on comment creation" do
      disable_feature_flag(:notifyd_enable_gist_events_for_actor)
      user = create(:user, :verified)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: user, created_at: 1.week.ago)
      assert_performed_with(job: SubscribeAndNotifyJob) do
        gist.comments.create(body: "This looks great!", user: @comment_user)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      mail = ActionMailer::Base.deliveries.last
      assert mail.destinations.include?(user.email)
      expected_subject = "Re: #{gist.name_with_title}"
      assert_match expected_subject, mail.subject
      assert_match "commented on", mail.html_part.body.decoded
    end

    test "notifies subscribers via email about a new comment on an anonymous gist" do
      disable_feature_flag(:notifyd_enable_gist_events_for_actor)
      # Make sure Ghost user exists
      User.create_ghost

      subscriber = create(:user, :verified)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: nil, created_at: 1.week.ago)
      gist.subscribe(subscriber, :manual)
      assert_performed_with(job: SubscribeAndNotifyJob) do
        gist.comments.create(body: "This is my commment", user: @comment_user)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      mail = ActionMailer::Base.deliveries.last
      assert mail.destinations.include?(subscriber.email)
      expected_subject = "Re: #{gist.name_with_title}"
      assert_match expected_subject, mail.subject
      assert_match "commented on", mail.html_part.body.decoded
    end

    test "subscribes commenters to the gist" do
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user, created_at: 1.week.ago)
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        gist.comments.create(body: "Great Gist!", user: @comment_user)
      end

      assert gist.subscribed?(@comment_user)
    end

    test "subscribes @mentioned users to the gist" do
      mentioned_user = create(:user)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user, created_at: 1.week.ago)
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        gist.comments.create(body: "Hey @#{mentioned_user.login} look at this!", user: @comment_user)
      end

      assert gist.subscribed?(mentioned_user)
    end

    test "subscribes @mentioned users to an anonymous gist" do
      # Make sure Ghost user exists
      User.create_ghost
      mentioned_user = create(:user)
      anonymous_gist = GistHelpers.generate(contents: gist_test_content_array, user: nil, created_at: 1.week.ago)
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        anonymous_gist.comments.create(body: "Hey @#{mentioned_user.login} look at this!", user: @comment_user)
      end

      assert anonymous_gist.subscribed?(mentioned_user)
    end

    test "notifies users via email when @mentioned in a comment of a gist" do
      disable_feature_flag(:notifyd_enable_gist_events_for_actor)

      mentioned_user = create(:user, :verified)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user, created_at: 1.week.ago)
      # We don't care about notification for the author in this test
      gist.unsubscribe(@user)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        gist.comments.create(body: "Hey @#{mentioned_user.login} look at this!", user: @comment_user)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      mail = ActionMailer::Base.deliveries.last
      assert mail.destinations.include?(mentioned_user.email)
      expected_subject = "Re: #{gist.name_with_title}"
      assert_match expected_subject, mail.subject
    end

    test "notifies users via email when @mentioned in a comment of an anonymous gist" do
      disable_feature_flag(:notifyd_enable_gist_events_for_actor)

      # Make sure Ghost user exists
      User.create_ghost
      mentioned_user = create(:user, :verified)
      anonymous_gist = GistHelpers.generate(contents: gist_test_content_array, user: nil, created_at: 1.week.ago)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        anonymous_gist.comments.create(body: "Hey @#{mentioned_user.login} look at this!", user: @comment_user)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size

      mail = ActionMailer::Base.deliveries.last
      assert mail.destinations.include?(mentioned_user.email)
      expected_subject = "Re: #{anonymous_gist.name_with_title}"
      assert_match expected_subject, mail.subject
    end

    test "subscribes newly @mentioned users to the gist on update" do
      mentioned_user = create(:user)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user, created_at: 1.week.ago)
      perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
        comment = gist.comments.create(body: "Boring comment", user: @comment_user)

        refute gist.subscribed?(mentioned_user)

        comment.body = "Hey @#{mentioned_user.login} look at this!"
        comment.save

        assert gist.subscribed?(mentioned_user)
      end
    end

    test "notifies users via email when newly @mentioned in a comment of a gist on update" do
      disable_feature_flag(:notifyd_enable_gist_events_for_actor)

      mentioned_user = create(:user, :verified)
      gist = GistHelpers.generate(contents: gist_test_content_array, user: @user, created_at: 1.week.ago)
      # We don't care about notification for the author in this test
      gist.unsubscribe(@user)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, UpdateSubscriptionsAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        comment = gist.comments.create(body: "A normal comment", user: @comment_user)

        assert_empty ActionMailer::Base.deliveries

        comment.body = "Hey @#{mentioned_user.login} look at this!"
        comment.save

        assert_equal 1, ActionMailer::Base.deliveries.size

        mail = ActionMailer::Base.deliveries.last
        assert mail.destinations.include?(mentioned_user.email)
        expected_subject = "Re: #{gist.name_with_title}"
        assert_match expected_subject, mail.subject
      end
    end
  end

  context "unminimize a comment" do
    test "only staff can unminimize staff-minimized comment" do
      @comment.update(comment_hidden_by: ROLES[:minimized_by_staff])
      refute @comment.async_unminimizable_by?(@user).sync
      assert @comment.async_unminimizable_by?(create(:staff_admin_user)).sync
    end

    test "owner & staff can unminimize owner-minimized comment" do
      @comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])

      random_user = create(:verified_user)
      refute @comment.async_unminimizable_by?(random_user).sync
      assert @comment.async_unminimizable_by?(@user).sync
      assert @comment.async_unminimizable_by?(create(:staff_admin_user)).sync
    end

    test "stores the right comment hidden by value" do

      author_minimized_comment = create(:gist_comment, gist: @gist, user: @user)
      author_minimized_comment.set_minimized(@user, "reason", "spam", @user, staff = false)
      staff_minimized_comment = create(:gist_comment, gist: @gist, user: @user)
      staff_minimized_comment.set_minimized(@staff_user, "reason", "spam", @user, @staff = true)

      assert_equal("minimized_by_maintainer", author_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_staff", staff_minimized_comment.comment_hidden_by)
    end
  end

  context "notification authorization" do
    test "allows any user to receive a notification" do
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: create(:user),
        subject: @comment,
      )

      assert_equal :ALLOW, decision.result
    end

    test "prevents spammy users from receiving a notification", skip_enterprise: true do
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: create(:spammy_user),
        subject: @comment,
      )

      assert_equal :DENY, decision.result
    end

    test "prevents suspended users from receiving a notification" do
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: create(:suspended_user),
        subject: @comment,
      )

      assert_equal :DENY, decision.result
    end
  end

  context "notification authorization v2" do
    test "allows any user to receive a notification" do
      recipient = create(:user)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": @user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :ALLOW, decision.result
    end

    test "prevents spammy users from receiving a notification", skip_enterprise: true do
      recipient = create(:spammy_user)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": @user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents suspended users from receiving a notification" do
      recipient = create(:suspended_user)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": @user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents spammy users from sending a notification", skip_enterprise: true do
      recipient = create(:user)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": create(:spammy_user).id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents suspended users from sending a notification" do
      recipient = create(:user)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": create(:suspended_user).id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents ignored users from sending a notification" do
      recipient = create(:user)
      recipient.block(@user)

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": @user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents ignored gist owners from sending a notification" do
      recipient = create(:user)
      recipient.block(@user)

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": create(:user).id, # this is not the owner of the gist
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "prevents bots from receiving a notification" do
      recipient = create(:bot)
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: recipient,
        subject: @comment,
        context: {
          version: 2,
          "notification.initiator.id": @user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end
  end
end
