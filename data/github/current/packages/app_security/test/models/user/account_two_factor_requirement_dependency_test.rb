# typed: true
# frozen_string_literal: true

require "test_helper"

class AccountTwoFactorRequirementDependencyTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    @plain_old_user = create(:user)
    @user_optional = create(:user)
    TwoFactorRequirementMetadata.create!(user: @user_optional, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:optional])
    @user_warning = create(:user)
    TwoFactorRequirementMetadata.create!(user: @user_warning, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
    @user_interrupt = create(:user)
    TwoFactorRequirementMetadata.create!(user: @user_interrupt, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:interrupt])
    @user_required = create(:user)
    TwoFactorRequirementMetadata.create!(user: @user_required, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
  end

  setup do
    enable_feature_flag(:bulwark_two_factor_required_feature)
  end

  context "#has_forthcoming_account_two_factor_requirement?" do
    test "returns true as expected" do
      assert @user_warning.has_forthcoming_account_two_factor_requirement?
      assert @user_interrupt.has_forthcoming_account_two_factor_requirement?
      assert @user_required.has_forthcoming_account_two_factor_requirement?
    end

    test "returns false as expected" do
      refute @user_optional.has_forthcoming_account_two_factor_requirement?
    end
  end

  context "#in_account_2fa_requirement_warning_state?" do
    test "returns true as expected" do
      assert @user_warning.in_account_2fa_requirement_warning_state?
    end

    test "returns false as expected" do
      refute @user_optional.in_account_2fa_requirement_warning_state?
    end
  end

  context "#in_account_2fa_requirement_interrupt_state?" do
    test "returns true as expected" do
      assert @user_interrupt.in_account_2fa_requirement_interrupt_state?
    end

    test "returns false as expected" do
      refute @user_optional.in_account_2fa_requirement_interrupt_state?
    end
  end

  context "#can_bypass_account_2fa_requirement_interrupt?" do
    test "always can bypass if state is NOT required" do
      assert @user_optional.can_bypass_account_2fa_requirement_interrupt?
      assert @user_warning.can_bypass_account_2fa_requirement_interrupt?
      assert @user_interrupt.can_bypass_account_2fa_requirement_interrupt?
    end

    test "can not bypass if state is required" do
      refute @user_required.can_bypass_account_2fa_requirement_interrupt?
    end
  end

  context "#account_2fa_requirement_interrupt_bypassed?" do
    test "returns true if value in KV for non required users" do
      GitHub::Authentication::KV.store.set(@user_optional.bypass_account_2fa_requirement_interrupt_key, "true")
      GitHub::Authentication::KV.store.set(@user_warning.bypass_account_2fa_requirement_interrupt_key, "true")
      GitHub::Authentication::KV.store.set(@user_interrupt.bypass_account_2fa_requirement_interrupt_key, "true")
      assert @user_optional.account_2fa_requirement_interrupt_bypassed?
      assert @user_warning.account_2fa_requirement_interrupt_bypassed?
      assert @user_interrupt.account_2fa_requirement_interrupt_bypassed?
    end

    test "returns false if value in KV for required user" do
      GitHub::Authentication::KV.store.set(@user_required.bypass_account_2fa_requirement_interrupt_key, "true")
      refute @user_required.account_2fa_requirement_interrupt_bypassed?
    end

    test "returns false if value not in KV" do
      refute @plain_old_user.account_2fa_requirement_interrupt_bypassed?
    end
  end

  context "#set_bypass_account_2fa_requirement_interrupt!" do
    test "sets kv value and updates metadata" do
      two_factor_requirement_metadata = create(:two_factor_requirement_metadata, user: @plain_old_user, requirement_reason: 1)

      refute @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 0, two_factor_requirement_metadata.interrupt_bypass_count

      @plain_old_user.set_bypass_account_2fa_requirement_interrupt!

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub::Authentication::KV.store.exists(@plain_old_user.bypass_account_2fa_requirement_interrupt_key)
      # rubocop:enable GitHub/DoNotUseGlobalKv
      assert @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 1, two_factor_requirement_metadata.interrupt_bypass_count
    end

    test "sets kv value and does not update metadata if bypass count is at max value" do
      two_factor_requirement_metadata = create(:two_factor_requirement_metadata, user: @plain_old_user, requirement_reason: 1, interrupt_bypass_count: 127)

      refute @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 127, two_factor_requirement_metadata.interrupt_bypass_count

      @plain_old_user.set_bypass_account_2fa_requirement_interrupt!

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub::Authentication::KV.store.exists(@plain_old_user.bypass_account_2fa_requirement_interrupt_key)
      # rubocop:enable GitHub/DoNotUseGlobalKv
      assert @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 127, two_factor_requirement_metadata.interrupt_bypass_count
    end

    test "does not update bypass count metadata if KV is unavailable" do
      two_factor_requirement_metadata = create(:two_factor_requirement_metadata, user: @plain_old_user, requirement_reason: 1)

      refute @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 0, two_factor_requirement_metadata.interrupt_bypass_count

      prevent_connections_to(ApplicationRecord::Authnd) do
        @plain_old_user.set_bypass_account_2fa_requirement_interrupt!
      end

      assert GitHub::Authentication::KV.store.exists(@plain_old_user.bypass_account_2fa_requirement_interrupt_key)
      refute @plain_old_user.account_2fa_requirement_interrupt_bypassed?
      assert_equal 0, two_factor_requirement_metadata.interrupt_bypass_count
    end
  end

  context "account_2fa_requirement_interrupt_required?" do
    test "returns false if optional or warning state" do
      refute @user_optional.account_2fa_requirement_interrupt_required?
      refute @user_warning.account_2fa_requirement_interrupt_required?
    end

    test "returns false if 2fa enabled for user that is in required state" do
      create(:two_factor_credential, user: @user_required)
      refute @user_required.account_2fa_requirement_interrupt_required?
    end

    test "returns false if 2fa enabled for user that is in interrupt state" do
      create(:two_factor_credential, user: @user_interrupt)
      refute @user_interrupt.account_2fa_requirement_interrupt_required?
    end

    test "returns true for user that is in required state that has recently bypassed (e.g. before they were transitions from 'interrupt' state" do
      @user_required.set_bypass_account_2fa_requirement_interrupt!
      assert @user_required.account_2fa_requirement_interrupt_required?
    end

    test "returns false for user that is in interrupt state that has bypassed" do
      @user_interrupt.set_bypass_account_2fa_requirement_interrupt!
      refute @user_interrupt.account_2fa_requirement_interrupt_required?
    end

    test "returns false for user that is in required state but not in feature flag" do
      disable_feature_flag(:bulwark_two_factor_required_feature)
      refute @user_required.account_2fa_requirement_interrupt_required?
    end

    test "returns false for user that is in interrupt state but not in feature flag" do
      disable_feature_flag(:bulwark_two_factor_required_feature)
      refute @user_interrupt.account_2fa_requirement_interrupt_required?
    end

    test "returns true for user that is in required state without 2fa enabled" do
      assert @user_required.account_2fa_requirement_interrupt_required?
    end

    test "returns true for user that is in interrupt state without 2fa enabled" do
      assert @user_interrupt.account_2fa_requirement_interrupt_required?
    end

    test "returns true if User has 2FA and has an account-based 2FA requirement" do
      required_user = create(:two_factor_credential_user)
      TwoFactorRequirementMetadata.create!(user: required_user, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])

      assert_predicate required_user, :in_account_2fa_requirement_required_state?
      refute_predicate required_user, :two_factor_auth_can_be_disabled?
    end

    test "returns true if User has 2FA and there is no account-based 2FA requirement" do
      optional_user = create(:two_factor_credential_user)
      TwoFactorRequirementMetadata.create!(user: optional_user, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:optional])
      warning_user = create(:two_factor_credential_user)
      TwoFactorRequirementMetadata.create!(user: warning_user, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
      interrupt_user = create(:two_factor_credential_user)
      TwoFactorRequirementMetadata.create!(user: interrupt_user, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:interrupt])
      exempt_user = create(:two_factor_credential_user)
      TwoFactorRequirementMetadata.create!(user: exempt_user, requirement_reason: "test", required_by: 1.week.from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:exempt])

      refute_predicate optional_user, :in_account_2fa_requirement_required_state?
      assert_predicate optional_user, :two_factor_auth_can_be_disabled?
      refute_predicate warning_user, :in_account_2fa_requirement_required_state?
      assert_predicate warning_user, :two_factor_auth_can_be_disabled?
      refute_predicate interrupt_user, :in_account_2fa_requirement_required_state?
      assert_predicate interrupt_user, :two_factor_auth_can_be_disabled?
      refute_predicate exempt_user, :in_account_2fa_requirement_required_state?
      assert_predicate exempt_user, :two_factor_auth_can_be_disabled?
    end
  end
end unless GitHub.enterprise?
