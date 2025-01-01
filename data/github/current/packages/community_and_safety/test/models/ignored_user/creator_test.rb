# typed: true
# frozen_string_literal: true

require "test_helper"

class IgnoredUser::CreatorTest < GitHub::TestCase
  fixtures do
    @user      = create(:user)
    @member    = create(:user)
    @blockable = create(:user)
    @org       = create(:organization, admin: @user, plan: GitHub::Plan.free)
    @team      = create(:team, organization: @org)
    @org_repo  = create(:repository, owner: @org)
    @org_issue = create(:issue, repository: @org_repo, user: @blockable)

    @org.add_member(@member)
  end

  context ".call" do
    test "user can successfully block a user" do
      result = IgnoredUser::Creator.call(
        blocker: @user,
        blockee: @blockable,
        actor: @user,
      )

      assert_predicate result, :success?
      assert_equal "#{@blockable.display_login} has been blocked.", result.message
      assert_empty result.errors
      block = result.block
      assert_equal @user, block.ignored_by
      assert_equal @blockable, block.ignored
      assert_nil block.expires_at
    end

    test "org can successfully block a user" do
      result = IgnoredUser::Creator.call(
        blocker: @org,
        blockee: @blockable,
        actor: @user,
      )

      message = "#{@blockable.display_login} has been blocked " \
                "from the #{@org.display_login} organization."

      assert_predicate result, :success?
      assert_equal message, result.message
      assert_empty result.errors
      block = result.block
      assert_equal @org, block.ignored_by
      assert_equal @blockable, block.ignored
      assert_nil block.expires_at
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "org moderator user can block a user" do
        refute @org.adminable_by?(@member)
        refute @org.moderator?(@member)
        refute @org.blocked_users_manageable_by?(@member)
        @org.moderation.add_moderator(@member, actor: @user)
        refute @org.adminable_by?(@member)
        assert @org.moderator?(@member)
        assert @org.blocked_users_manageable_by?(@member)

        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @member,
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_nil block.expires_at
      end


      test "org moderator via team can block a user" do
        assert @team.add_member(@member)
        refute @org.adminable_by?(@member)
        refute @org.moderator?(@member)
        refute @org.blocked_users_manageable_by?(@member)
        @org.moderation.add_moderator(@team, actor: @user)
        refute @org.adminable_by?(@member)
        assert @org.moderator?(@member)
        assert @org.blocked_users_manageable_by?(@member)

        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @member,
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_nil block.expires_at
      end
    end

    test "org can successfully block a user from content" do
      result = IgnoredUser::Creator.call(
        blocker: @org,
        blockee: @blockable,
        actor: @user,
        blocked_from_content: @org_issue,
      )

      message = "#{@blockable.display_login} has been blocked " \
                "from the #{@org.display_login} organization."

      assert_predicate result, :success?
      assert_equal message, result.message
      assert_empty result.errors
      block = result.block
      assert_equal @org, block.ignored_by
      assert_equal @blockable, block.ignored
      assert_equal @org_issue, block.blocked_from_content
      assert_nil block.expires_at
    end

    test "org can successfully block a user with a specified duration" do
      Timecop.freeze do
        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @user,
          duration: 1,
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization for 1 day."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_equal 1.day.from_now.to_i, block.expires_at.to_i
      end
    end

    test "org can successfully block a user and send notification" do
      Timecop.freeze do
        AccountMailer.expects(:blocked_by_org).once.with(
          @org,
          @blockable,
          nil,
          " for 1 day",
        ).returns(stub(deliver_later: nil))

        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @user,
          duration: 1,
          send_notification: true,
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization for 1 day " \
                  "and will receive an email notification."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_equal 1.day.from_now.to_i, block.expires_at.to_i
      end
    end

    test "blocking user and notifying for top level issue creates issue event" do
      Timecop.freeze do
        AccountMailer.expects(:blocked_by_org).once.with(
          @org,
          @blockable,
          @org_issue,
          " for 1 day",
        ).returns(stub(deliver_later: nil))

        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @user,
          duration: 1,
          blocked_from_content: @org_issue,
          send_notification: true,
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization for 1 day " \
                  "and will receive an email notification."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_equal 1.day.from_now.to_i, block.expires_at.to_i
        assert @org_issue.events.find_by(event: "user_blocked")
      end
    end

    test "org can successfully block a user and minimize comments" do
      Timecop.freeze do
        result = IgnoredUser::Creator.call(
          blocker: @org,
          blockee: @blockable,
          actor: @user,
          duration: 1,
          send_notification: true,
          minimize_comments: true,
          minimize_reason: "OFF_TOPIC",
          note: "This is why they're blocked!",
        )

        message = "#{@blockable.display_login} has been blocked " \
                  "from the #{@org.display_login} organization for 1 day " \
                  "and will receive an email notification. " \
                  "Their comments have been hidden as off-topic."

        assert_predicate result, :success?
        assert_equal message, result.message
        assert_empty result.errors
        block = result.block
        assert_equal @org, block.ignored_by
        assert_equal @blockable, block.ignored
        assert_equal 1.day.from_now.to_i, block.expires_at.to_i
        assert_equal "This is why they're blocked!", block.note
      end
    end

    test "returns error if blocker is missing" do
      result = IgnoredUser::Creator.call(
        blocker: nil,
        blockee: @blockable,
        actor: @user,
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Blocker can't be blank"], result.errors
    end

    test "returns error if blockee is missing" do
      result = IgnoredUser::Creator.call(
        blocker: @user,
        blockee: nil,
        actor: @user,
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Blockee can't be blank"], result.errors
    end

    test "returns error if actor is missing" do
      result = IgnoredUser::Creator.call(
        blocker: @user,
        blockee: @blockable,
        actor: nil,
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Actor can't be blank"], result.errors
    end

    test "returns error if actor is not authorized" do
      result = IgnoredUser::Creator.call(
        blocker: @user,
        blockee: @blockable,
        actor: create(:user),
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Actor is not authorized to block users"], result.errors
    end

    test "returns error if minimize reason is invalid" do
      result = IgnoredUser::Creator.call(
        blocker: @org,
        blockee: @blockable,
        actor: @user,
        minimize_comments: true,
        minimize_reason: "hu-tao"
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Minimize reason must be a valid reason"], result.errors
    end

    test "returns validation error from IgnoredUser record" do
      result = IgnoredUser::Creator.call(
        blocker: @user,
        blockee: @user,
        actor: @user,
      )

      refute_predicate result, :success?
      assert_nil result.message
      assert_equal ["Blocked user cannot be the blocking user"], result.errors
    end
  end
end
