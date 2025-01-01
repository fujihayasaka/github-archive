# typed: true
# frozen_string_literal: true

require "test_helper"

class TestTwoFactorAuthnPolicy
  include ConditionalAccess::Policy::TwoFactorAuthn

  def initialize(current_user: nil)
    @current_user = current_user
  end

  def actor
    @current_user
  end

  def anonymous?
    !@current_user
  end

  def location
    :test
  end

  def callback_name
    "test"
  end
end

class CapTwoFactorAuthnPolicyTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @org = create :business_plus_org, admin: @owner

    @direct_member_with_2fa = create :user, login: "sms-me"
    make_two_factor_credential(@direct_member_with_2fa)
    @direct_member_without_2fa = create :user, login: "no-two-factor"

    @org.add_member @direct_member_with_2fa
    @org.add_member @direct_member_without_2fa

    @org.enable_two_factor_required(actor: @owner)
    assert @org.member?(@direct_member_without_2fa)
  end

  setup do
    @policy = TestTwoFactorAuthnPolicy.new(current_user: @direct_member_with_2fa)
    GitHub.flipper[:cap_2fa_policy_enabled].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable(@org)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")
  end

  context "feature flag" do
    test "not applicable when killswitch is disabled" do
      GitHub.flipper[:cap_2fa_policy_enabled].disable
      assert_equal :no, @policy.two_factor_applicable(resource: @org, target_provider: @target_provider)
    end

    test "applicable when global killswitch is enabled" do
      assert_predicate GitHub.flipper[:cap_2fa_policy_enabled], :enabled?
      assert_equal :yes, @policy.two_factor_applicable(resource: @org, target_provider: @target_provider)
    end

    test "killswitch shortcuts multiple 2fa applicable" do
      GitHub.flipper[:cap_2fa_policy_enabled].disable

      @policy.expects(:two_factor_applicable).never

      result = @policy.multiple_two_factor_applicable([@org], @target_provider)
      assert_empty result
    end

    test "2FA policy is applicable when global killswitch enabled" do
      assert_predicate GitHub.flipper[:cap_2fa_policy_enabled], :enabled?

      results = @policy.multiple_two_factor_applicable([@org], @target_provider)
      assert_same_elements [@org], results
    end
  end
end
