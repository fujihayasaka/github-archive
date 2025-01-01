# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.enterprise?
  class GlobalNoticeNext::VerifiedEmailsCheckTest < GitHub::TestCase
    context "#should_show_notice?" do
      test "returns false if user has a verified email" do
        user = create :user, :verified, plan: "small"

        check = GlobalNoticeNext::VerifiedEmailsCheck.new(viewer: user)

        refute check.should_show_notice?
      end

      test "returns true if user has no verified emails" do
        user = create :user, plan: "small"

        check = GlobalNoticeNext::VerifiedEmailsCheck.new(viewer: user)

        assert check.should_show_notice?
      end

      test "returns true if mandatory email verifications is enabled" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)

        user = create :user, plan: "small"
        user.update_column :created_at, 1.hour.ago # We don't care about verified emails until the user is 30 min old
        assert user.show_verification_reminder?

        check = GlobalNoticeNext::VerifiedEmailsCheck.new(viewer: user)

        assert check.should_show_notice?
      end

      if GitHub.enterprise?
        test "does not enqueue email verification reminder job" do
          user = create :user, plan: "small", created_at: 1.month.ago
          assert user.show_verification_reminder?

          assert_no_enqueued_jobs do
            GlobalNoticeNext::VerifiedEmailsCheck.new(viewer: user).should_show_notice?
          end
        end
      else
        test "enqueues email verification reminder job" do
          user = create :user, plan: "small", created_at: 1.month.ago
          assert user.show_verification_reminder?

          assert_enqueued_with(job: UserSignupFollowupJob, args: [user], queue: "user_signup_followup") do
            GlobalNoticeNext::VerifiedEmailsCheck.new(viewer: user).should_show_notice?
          end
        end
      end
    end
  end
end
