# typed: true
# frozen_string_literal: true

require "test_helper"

class FollowerAndFollowingAggregateCountsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @spammy_user = create(:user)
    @staff = create :staff_admin_user
  end

  # We need to find and re-instantiate the User object in order to reset cached counts.
  # User#reload re-fetches object attributes from the database but does not re-instantiate the
  # object.
  def reload_user(user)
    User.find(user.id)
  end

  unless GitHub.enterprise?
    test "doesn't count spammy user in regular user followers count" do
      @spammy_user.follow(@user)
      assert_equal 1, reload_user(@user).followers_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @user.followers_count!
      assert_equal 0, reload_user(@user).followers_count(viewer: nil)
    end

    test "doesn't count spammy user in regular user following count" do
      @user.follow(@spammy_user)
      assert_equal 1, reload_user(@user).following_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @user.following_count!
      assert_equal 0, reload_user(@user).following_count(viewer: nil)
    end

    test "hides spammy user followers count" do
      @user.follow(@spammy_user)
      assert_equal 1, reload_user(@spammy_user).followers_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @spammy_user.followers_count!
      assert_equal 0, reload_user(@spammy_user).followers_count(viewer: nil)
    end

    test "hides spammy user followings count" do
      @spammy_user.follow(@user)
      assert_equal 1, reload_user(@spammy_user).following_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @spammy_user.following_count!
      assert_equal 0, reload_user(@spammy_user).following_count(viewer: nil)
    end

    test "returns 0 followers for private users" do
      @private_user = create(:user)
      @user.follow(@private_user)
      assert_equal 1, reload_user(@private_user).followers_count(viewer: nil)
      @private_user.update!(private_profile: true)
      assert_equal 0, reload_user(@user).followers_count(viewer: nil)
    end

    test "returns 0 followings for private users" do
      @private_user = create(:user)
      @private_user.follow(@user)
      assert_equal 1, reload_user(@private_user).following_count(viewer: nil)
      @private_user.update!(private_profile: true)
      assert_equal 0, reload_user(@private_user).following_count(viewer: nil)
    end
  end
end
