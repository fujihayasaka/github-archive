# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RecalculateUserFollowersCacheJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @another_user = create(:user)

    @user.follow(@other_user)
    @user.follow(@another_user)
  end

  test "refreshes followers count for each user ID specified" do
    @other_user.followers_count!
    @another_user.followers_count!

    @user.following.destroy_all
    assert_equal 1, @other_user.followers_count(viewer: nil)
    assert_equal 1, @another_user.followers_count(viewer: nil)

    RecalculateUserFollowersCacheJob.perform_now(user_ids: [@other_user.id, @another_user.id])

    assert_equal 0, @other_user.followers_count(viewer: nil)
    assert_equal 0, @another_user.followers_count(viewer: nil)
  end

  test "handles case where user no longer exists" do
    @other_user.followers_count!
    @another_user.followers_count!

    assert_equal 1, @other_user.followers_count(viewer: nil)
    assert_equal 1, @another_user.followers_count(viewer: nil)

    @another_user.destroy!
    @user.following.destroy_all

    RecalculateUserFollowersCacheJob.perform_now(user_ids: [@other_user.id, @another_user.id])

    assert_equal 0, @other_user.followers_count(viewer: nil)
    assert_equal 0, @another_user.followers_count(viewer: nil)
  end
end
