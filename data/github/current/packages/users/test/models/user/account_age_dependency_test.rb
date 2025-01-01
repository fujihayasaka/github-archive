# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAccountAgeDependencyTest < GitHub::TestCase
  context ".joined_in_last_month?" do
    test "returns false when the user joined over a month ago" do
      user = create(:user, created_at: 1.year.ago)

      refute_predicate user, :joined_in_last_month?
    end

    test "returns true when the user joined less than a month ago" do
      user = create(:user, created_at: 1.day.ago)

      assert_predicate user, :joined_in_last_month?
    end
  end

  context ".zero_user?" do
    test "returns false when the user is before the zero user start date" do
      date_before_zero_user_start = User::AccountAgeDependency::ZERO_USER_START_DATE - 1.year
      user = create(:user, created_at: date_before_zero_user_start)

      refute_predicate user, :zero_user?
    end

    test "returns true when the user is after the zero user start date" do
      date_after_zero_user_start = User::AccountAgeDependency::ZERO_USER_START_DATE + 1.year
      user = create(:user, created_at: date_after_zero_user_start)

      assert_predicate user, :zero_user?
    end
  end

  context ".in_onboarding_period?" do
    test "returns true when the user account age is within the onboarding period" do
      user = create(:user, created_at: 1.day.ago)

      assert_predicate user, :in_onboarding_period?
    end

    test "returns falese when the user account age is outside the onboarding priod" do
      user = create(:user, created_at: 1.year.ago)

      refute_predicate user, :in_onboarding_period?
    end

    unless GitHub.enterprise? || GitHub.multi_tenant_enterprise?
      test "returns true when user is an employee and has nux_tester feature enabled" do
        employee = create(:employee, created_at: 1.year.ago)
        enable_feature_flag(:nux_tester, employee)

        assert_predicate employee, :in_onboarding_period?
      end

      test "defers to account age when user is an employee and has nux_tester feature disabled" do
        new_employee = create(:employee, created_at: 1.day.ago)
        old_employee = create(:employee, created_at: 1.year.ago)
        disable_feature_flag(:nux_tester, new_employee)
        disable_feature_flag(:nux_tester, old_employee)

        assert_predicate new_employee, :in_onboarding_period?
        refute_predicate old_employee, :in_onboarding_period?
      end
    end

    test "defers to account age when nux_tester feature enabled and user not an employee" do
      new_user = create(:user, created_at: 1.day.ago)
      old_user = create(:user, created_at: 1.year.ago)
      enable_feature_flag(:nux_tester, new_user)
      enable_feature_flag(:nux_tester, old_user)

      assert_predicate new_user, :in_onboarding_period?
      refute_predicate old_user, :in_onboarding_period?
    end
  end
end
