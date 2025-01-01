# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSpamDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
  end

  context "spammy notice" do
    test "sets spammy notice if user is spammy" do
      user = create(:user)
      user.spammy = true
      user.save

      assert_equal :spammy, GlobalNoticeNext.new(viewer: user).current_notice_name
    end

    test "does not set spammy notice if user is not spammy" do
      user = create(:user)
      user.spammy = false
      user.save

      assert_nil GlobalNoticeNext.new(viewer: user).current_notice_name
    end
  end if GitHub.spamminess_check_enabled?

  context "#delay_deletion_for_spam_checks?" do
    if GitHub.spamminess_check_enabled?
      test "true for user that recently updated an issue" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:issue,
          user: @user,
          created_at: 1.month.ago,
          updated_at: 12.hours.ago,
        )
        assert_predicate @user, :delay_deletion_for_spam_checks?
      end

      test "true for user that recently updated an issue comment" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:issue_comment,
          user: @user,
          created_at: 8.hours.ago,
          updated_at: 8.hours.ago,
        )
        assert_predicate @user, :delay_deletion_for_spam_checks?
      end

      test "true for user that recently updated a discussion" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:discussion,
          user: @user,
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago
        )
        assert_predicate @user, :delay_deletion_for_spam_checks?
      end

      test "true for user that recently updated a discussion comment" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:discussion_comment,
          user: @user,
          created_at: 2.days.ago,
          updated_at: 5.minutes.ago
        )
        assert_predicate @user, :delay_deletion_for_spam_checks?
      end

      test "false for user that updated content over 24 hours ago" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:discussion_comment,
          user: @user,
          created_at: 3.days.ago,
          updated_at: 2.days.ago,
        )
        refute_predicate @user, :delay_deletion_for_spam_checks?
      end

      test "false for EMU" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        emu = create(:emu)
        create(:discussion_comment,
          user: emu,
          created_at: 2.minutes.ago,
          updated_at: 2.minutes.ago,
        )
        refute_predicate emu, :delay_deletion_for_spam_checks?
      end

      test "false if feature flag is disabled" do
        disable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:discussion_comment,
          user: @user,
          created_at: 2.minutes.ago,
          updated_at: 2.minutes.ago,
        )
        refute_predicate @user, :delay_deletion_for_spam_checks?
      end
    else
      test "returns false if spam checking is disabled" do
        enable_feature_flag(:delay_user_deletion_for_spam_checks)

        create(:discussion,
          user: @user,
          created_at: 8.hours.ago,
          updated_at: 8.hours.ago,
        )
        refute_predicate @user, :delay_deletion_for_spam_checks?
      end
    end
  end
end
