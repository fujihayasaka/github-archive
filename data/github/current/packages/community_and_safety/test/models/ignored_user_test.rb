# typed: true
# frozen_string_literal: true

require "test_helper"

class IgnoredUserTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create :user
    @member = create :user
    @org = create :organization
    @org.add_member @member
    @repo = create :repository, owner: @org
    @blocked_user = create :user
  end

  test "blocking a user" do
    @user.block @blocked_user
    assert @user.avoid? @blocked_user
    assert_equal 1, @user.ignored_users.count
    assert_equal 1, @user.ignored.count
    assert_equal 1, @blocked_user.ignored_by_users.count
    assert_equal 1, @blocked_user.ignored_by.count
    assert_includes IgnoredUser.blocking(@blocked_user).pluck(:user_id), @user.id
    refute_includes IgnoredUser.blocking(@user).pluck(:user_id), @blocked_user.id
    assert_includes IgnoredUser.blocked_by(@user).pluck(:ignored_id), @blocked_user.id
    refute_includes IgnoredUser.blocked_by(@blocked_user).pluck(:ignored_id), @user.id
  end

  test "unblocking a user" do
    @user.block @blocked_user
    assert @user.avoid? @blocked_user

    @user.unblock @blocked_user
    refute @user.avoid? @blocked_user
    assert_equal 0, @user.ignored_users.count
    assert_equal 0, @user.ignored.count
    assert_equal 0, @blocked_user.ignored_by_users.count
    assert_equal 0, @blocked_user.ignored_by.count
  end

  test "stores the created_at timestamp" do
    @user.block @blocked_user
    assert_equal 1, @user.ignored_users.count
    assert @user.ignored_users.first.created_at
  end

  test "default scope only returns unexpired users" do
    expired_user = create(:user)
    unexpired_user = create(:user)
    @org.block(@blocked_user)
    @org.block(expired_user, duration: 1)
    @org.block(unexpired_user, duration: 7)

    Timecop.freeze(1.day.from_now + 1.minute) do
      assert_equal 3, IgnoredUser.unscoped.where(ignored_by: @org).count
      assert_equal 2, @org.ignored_users.count
      assert_includes @org.ignored, unexpired_user
      assert_includes @org.ignored, @blocked_user
      refute_includes @org.ignored, expired_user
    end
  end

  test "blocked from content not owned by user an error is raised" do
    user = create(:user)
    issue = create(:issue)

    block = @org.block(user, blocked_from_content: issue)
    refute block.valid?
    assert block.errors.added?(:blocked_from_content, "must be owned by blocked user")
  end

  test "blocked from content emails user" do
    user = create(:user)
    issue = create(:issue, user: user, repository: @repo)

    AccountMailer.expects(:blocked_by_org).returns(stub(deliver_later: nil))

    @org.block(user, blocked_from_content: issue, send_notification: true)
  end

  test "blocked from content creates a timeline event if send_notification is true" do
    user = create(:user)
    issue = create(:issue, user: user, repository: @repo)
    issue_comment = create(:issue_comment, issue: issue)
    duration = 7
    assert_difference "IssueEvent.count", 1 do
      @org.block(user, blocked_from_content: issue_comment, send_notification: true, duration: duration)
    end

    event = issue.events.last
    assert_equal "user_blocked", event.event
    assert_equal @org, event.actor
    assert_equal user, event.subject
    assert_equal duration, event.block_duration_days
  end

  test "blocked from top level issue creates a timeline event if send_notification is true" do
    user = create(:user)
    issue = create(:issue, user: user, repository: @repo)
    duration = 7
    assert_difference "IssueEvent.count", 1 do
      @org.block(
        user,
        blocked_from_content: issue,
        send_notification: true,
        duration: duration,
      )
    end

    event = issue.events.last
    assert_equal "user_blocked", event.event
    assert_equal @org, event.actor
    assert_equal user, event.subject
    assert_equal duration, event.block_duration_days
  end

  test "blocked from content does not create a timeline event if send_notification is false" do
    user = create(:user)
    issue = create(:issue, user: user, repository: @repo)
    issue_comment = create(:issue_comment, issue: issue)
    duration = 7
    assert_no_difference "IssueEvent.count" do
      @org.block(user, blocked_from_content: issue_comment, send_notification: false, duration: duration)
    end
  end

  test "blocked from content does not create a timeline event if content does not have an issue" do
    user = create(:user)
    commit_comment = create(:commit_comment, repository: @repo)
    duration = 7

    assert_no_difference "IssueEvent.count" do
      @org.block(user, blocked_from_content: commit_comment, send_notification: true, duration: duration)
    end
  end

  test "does not email user if actor blocked by ignored user" do
    user = create(:user)
    issue = create(:issue, user: user, repository: @repo)
    user.block(@org.admin)

    AccountMailer.expects(:blocked_by_org).never

    @org.block(user, blocked_from_content: issue, actor: @org.admin)
  end

  test "does not notify user on block if content not set" do
    org = create(:organization)
    rando = create(:user)

    assert_no_difference("ActionMailer::Base.deliveries.size") { org.block(rando, actor: org.admin) }
  end

  context "validation" do
    test "cannot block non-users" do
      block = @user.block(@org)
      refute block.valid?
      assert block.errors.added?(:ignored, "is not a user")
    end

    test "cannot block org member" do
      block = @org.block(@member)
      refute block.valid?
      assert block.errors.added?(:ignored, "is an organization member")
    end

    test "cannot block org billing manager" do
      billing_manager = create(:verified_user)
      @org.billing.add_manager(billing_manager, actor: @org.admin)
      assert @org.billing_manager?(billing_manager)

      block = @org.block(billing_manager)
      refute block.valid?
      assert block.errors.added?(:ignored, "is a billing manager of this organization")
    end

    test "cannot block if already perma blocking" do
      @user.block(@blocked_user)
      block = @user.block(@blocked_user)
      refute block.valid?
      assert block.errors.added?(:ignored, "has already been blocked")
    end

    test "cannot block if already temp blocking" do
      @org.block(@blocked_user, duration: 1)
      block = @org.block @blocked_user
      refute block.valid?
      assert block.errors.added?(:ignored, "has already been blocked")
    end

    test "must unblock to upgrade a temporary block to a permanent block" do
      @org.block(@blocked_user, duration: 3)
      assert block = @org.block(@blocked_user)
      refute block.valid?

      assert_difference "IgnoredUser.count", -1 do
        assert @org.unblock(@blocked_user)
      end

      assert_difference "IgnoredUser.count", 1 do
        @org.block(@blocked_user)
      end

      block = IgnoredUser.where(ignored_by: @org).first
      assert_nil T.must(block).expires_at
      assert_equal @blocked_user, T.must(block).ignored
    end

    test "cannot block yourself" do
      block = @user.block(@user)
      refute block.valid?
      assert block.errors.added?(:ignored, "cannot be the blocking user")
    end

    if GitHub.spamminess_check_enabled?
      test "spammy users cannot block" do
        @user.mark_as_spammy
        block = @user.block(@blocked_user)
        refute block.valid?
        assert block.errors.added?(:ignored_by, "has been flagged as spam")
      end

      test "cannot block spammy user if spammy user is not visible" do
        @blocked_user.mark_as_spammy
        assert_predicate @blocked_user, :spammy?
        assert @blocked_user.hide_from_user?(@user)

        block = @user.block(@blocked_user)
        refute_predicate block, :valid?
        assert block.errors.added?(:ignored, "has been flagged as spam")
      end

      test "site admin can block spammy user" do
        staff = create(:staff_admin_user)
        @blocked_user.mark_as_spammy
        assert_predicate @blocked_user, :spammy?
        refute @blocked_user.hide_from_user?(staff)

        block = staff.block(@blocked_user)
        assert_predicate block, :valid?
      end
    end

    test "blocking user must have a verified email" do
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @user.require_email_verification!
      @user.emails.each(&:unverify!)

      block = @user.block(@blocked_user)
      refute block.valid?
      assert block.errors.added?(:ignored_by, "cannot block without a verified email")
    end if GitHub.email_verification_enabled?

    test "time-limited blocks are limited to orgs" do
      expires_at = 3.days.from_now
      block = @user.block(@blocked_user, duration: 3)
      refute block.valid?
      assert block.errors.added?(:ignored_by, "cannot create a time-limited block")
    end

    test "cannot provide an invalid duration" do
      block = @user.block(@blocked_user, duration: 1337)
      refute block.valid?
      assert block.errors.added?(:expires_at, "is invalid")
    end
  end

  context "instrumentation" do
    test "instruments create for a user" do
      events = subscribe "user.block_user"
      assert @user.block @blocked_user

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @blocked_user.login,
        blocked_user_id: @blocked_user.id,
        user: @user.login,
        user_id: @user.id,
        expires_at: nil,
        duration: nil,
        spammy: false,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        send_notification: false,
        minimize_reason: nil,
        code_of_conduct_status: "unknown",
      }

      assert event = events.pop, "an event should've been created"
      assert_equal "user.block_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments destroy for a user" do
      @user.block @blocked_user
      events = subscribe "user.unblock_user"
      assert @user.unblock @blocked_user

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @blocked_user.login,
        blocked_user_id: @blocked_user.id,
        user: @user.login,
        user_id: @user.id,
        spammy: false,
      }

      assert event = events.pop, "an event should've been created"
      assert_equal "user.unblock_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments a block with a duration" do
      events = subscribe "org.block_user"
      block = IgnoredUser.create!({
        ignored_by: @org, ignored: @blocked_user,
        actor: @user, expires_at: 3.days.from_now
      })

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @blocked_user.login,
        blocked_user_id: @blocked_user.id,
        org: @org.login,
        org_id: @org.id,
        expires_at: block.expires_at,
        spammy: false,
        duration: 3,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        send_notification: nil,
        minimize_reason: nil,
        code_of_conduct_status: "unknown",
      }

      assert event = events.pop, "an event should've been created"
      assert_equal "org.block_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments create for an org" do
      events = subscribe "org.block_user"
      assert @org.block @blocked_user, actor: @user

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @blocked_user.login,
        blocked_user_id: @blocked_user.id,
        org: @org.login,
        org_id: @org.id,
        expires_at: nil,
        duration: nil,
        spammy: false,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        send_notification: false,
        minimize_reason: nil,
        code_of_conduct_status: "unknown",
      }

      assert event = events.pop, "an event should've been created"
      assert_equal "org.block_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments destroy for an org" do
      @org.block @blocked_user, actor: @user
      events = subscribe "org.unblock_user"
      assert @org.unblock @blocked_user, actor: @user

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @blocked_user.login,
        blocked_user_id: @blocked_user.id,
        org: @org.login,
        org_id: @org.id,
        spammy: false,
      }

      assert event = events.pop, "an event should've been created"
      assert_equal "org.unblock_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "calculates duration" do
      expires_at = 3.days.from_now
      block = IgnoredUser.create!(ignored_by: @org, ignored: @blocked_user, expires_at: expires_at)
      assert_equal 3, block.duration
    end
  end

  context "hydro instrumentation" do
    test "instruments create when blocking a user and no specific content" do
      assert @user.block(@blocked_user, minimize_reason: "spam")

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: Hydro::EntitySerializer.user(@user),
        expires_at: nil,
        action: :ACTION_IGNORED_USER_CREATED,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        minimize_reason: "spam",
        repository: nil
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end

    test "instruments destroy for a user unblock" do
      @user.block @blocked_user
      assert @user.unblock @blocked_user

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: Hydro::EntitySerializer.user(@user),
        expires_at: nil,
        action: :ACTION_IGNORED_USER_DELETED,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        minimize_reason: nil,
        repository: nil
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end

    test "instruments create when blocking a user from an org" do
      @org.block(@blocked_user, actor: @user)

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: nil,
        ignored_by_org: Hydro::EntitySerializer.organization(@org),
        expires_at: nil,
        action: :ACTION_IGNORED_USER_CREATED,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        minimize_reason: nil,
        repository: nil,
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end

    test "instruments destroy when unblocking a user from an org" do
      @org.block(@blocked_user, actor: @user)
      assert @org.unblock(@blocked_user, actor: @user)

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: nil,
        ignored_by_org: Hydro::EntitySerializer.organization(@org),
        expires_at: nil,
        action: :ACTION_IGNORED_USER_DELETED,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        minimize_reason: nil,
        repository: nil,
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end

    test "instruments create when blocking specific content in an org" do
      issue = create(:issue, user: @blocked_user, repository: @repo)

      @org.block(@blocked_user, blocked_from_content: issue, actor: @user)

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: nil,
        ignored_by_org: Hydro::EntitySerializer.organization(@org),
        expires_at: nil,
        action: :ACTION_IGNORED_USER_CREATED,
        blocked_from_content_id: issue.id,
        blocked_from_content_type: "Issue",
        minimize_reason: nil,
        repository: Hydro::EntitySerializer.repository(@repo),
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end

    test "instruments create with a duration when blocking for a period of time" do
      block = IgnoredUser.create!({
        ignored_by: @org, ignored: @blocked_user,
        actor: @user, expires_at: 3.days.from_now
      })

      expected_payload = {
        actor: Hydro::EntitySerializer.user(@user),
        ignored: Hydro::EntitySerializer.user(@blocked_user),
        ignored_by: nil,
        ignored_by_org: Hydro::EntitySerializer.organization(@org),
        expires_at: block.expires_at,
        action: :ACTION_IGNORED_USER_CREATED,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        minimize_reason: nil,
        repository: nil,
      }

      assert_hydro_published(expected_payload, schema: "github.v1.IgnoredUser")
    end
  end

  test "cannot perma-block a user that was temp blocked" do
    blockee = create(:user)

    assert @org.block(blockee, duration: 7)
    block = @org.block(blockee)
    refute block.valid?
    assert block.errors.added?(:ignored, "has already been blocked")
  end

  test "can perma-block a user that has an expired temp block" do
    blockee = create(:user)
    expired_block = @org.block(blockee, duration: 1)
    assert expired_block.valid?

    Timecop.freeze(1.day.from_now + 1.minute) do
      permanent_block = @org.block(blockee)
      assert permanent_block.valid?
    end
  end

  test "creating a new block enqueues a job to clear graph data" do
    assert_enqueued_with(job: ClearGraphDataOnBlockJob, args: [@user.id, @blocked_user.id]) do
      IgnoredUser.create!(
        ignored_by: @user,
        ignored: @blocked_user,
        actor: @user,
      )
    end
  end

  test "destroying a block enqueues a job to clear graph data" do
    block = IgnoredUser.create!(
      ignored_by: @user,
      ignored: @blocked_user,
      actor: @user,
    )
    assert_enqueued_with(job: ClearGraphDataOnBlockJob, args: [@user.id, @blocked_user.id]) do
      block.destroy
    end
  end

  test "creating a new block with a minimize_reason enqueues job to minimize comments" do
    assert_enqueued_with(
      job: MinimizeAllCommentsOnRepoJob,
      args: [@org, @blocked_user, @user, "spam"],
    ) do
      IgnoredUser.create!(
        ignored_by: @org,
        ignored: @blocked_user,
        minimize_reason: "spam",
        actor: @user,
      )
    end
  end

  test "creating a new block without a minimize_reason does not enqueue job" do
    assert_no_enqueued_jobs(only: MinimizeAllCommentsOnRepoJob) do
      IgnoredUser.create!(
        ignored_by: @org,
        ignored: @blocked_user,
        actor: @user,
      )
    end
  end

  test "invalidates feed cache when a user is blocked" do
    Conduit::KVBackedCache.get_or_set_for(@user) { "cached-value" }

    IgnoredUser.create!(
      ignored_by: @user,
      ignored: @blocked_user,
      actor: @user,
    )

    assert_equal Conduit::KVBackedCache.get_or_set_for(@user) { "expected-value" }, "expected-value"
  end
end
