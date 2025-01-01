# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class GlobalNoticeNextRefreshJobTest < GitHub::TestCase
    test "runs global notice next refresh for given user" do
      user = create(:user)
      user.global_notice.destroy if user.global_notice.persisted?

      refute user.global_notice.set?, "Expected notice to not be set"

      GlobalNoticeNextRefreshJob.perform_now(user.id)

      assert user.reload.global_notice.set?, "Expected notice to be set"
    end

    test "locks job based on user id" do
      user = create(:user)
      GitHub::Restraint.any_instance.expects(:lock!).with("global-notice-next-refresh-for-#{user.id}", 1, 5.minutes)

      GlobalNoticeNextRefreshJob.perform_now(user.id)
    end

    test "doesn't error if user is deleted" do
      user = create(:user)
      user_id = user.id
      user.destroy
      GlobalNoticeNextRefreshJob.perform_now(user_id)
    end

    test "does not allow concurrent jobs for the same user" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)

      assert_enqueued_jobs 1, only: GlobalNoticeNextRefreshJob do
        GlobalNoticeNextRefreshJob.set(wait: 5.minutes).perform_later(user.id)
        GlobalNoticeNextRefreshJob.set(wait: 5.minutes).perform_later(user.id)
        GlobalNoticeNextRefreshJob.perform_later(user.id)
      end
    end
  end
end
