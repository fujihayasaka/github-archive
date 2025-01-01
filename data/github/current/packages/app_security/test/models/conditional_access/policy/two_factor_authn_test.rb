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
    if GitHub.two_factor_sms_enabled?
      make_two_factor_credential_both_otp_methods(@direct_member_with_2fa)
    else
      make_two_factor_credential(@direct_member_with_2fa)
    end
    @direct_member_without_2fa = create :user, login: "no-two-factor"

    @org.add_member @direct_member_with_2fa
    @org.add_member @direct_member_without_2fa

    @org.enable_two_factor_requirement(actor: @owner)
    assert @org.member?(@direct_member_without_2fa)
  end

  setup do
    @policy = TestTwoFactorAuthnPolicy.new(current_user: @direct_member_with_2fa)
    @policy_user_no_2fa = TestTwoFactorAuthnPolicy.new(current_user: @direct_member_without_2fa)
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

  context "#multiple_two_factor_satisfied" do
    test "analyzes correctly" do
      GitHub.flipper[:cap_2fa_policy_enabled].enable
      GitHub.flipper[:two_factor_cap_enforcement].enable
      @org.add_disallowed_two_factor_method(method: :sms, actor: @owner) if GitHub.two_factor_sms_enabled?
      GitHub.flipper[:enforce_disallow_two_factor_methods].enable(@org) # not satisfied if disallowed method configured
      org2 = create(:organization, admin: @owner)
      org2.enable_two_factor_requirement(actor: @owner)
      org2.add_member(@direct_member_with_2fa) # basic 2FA requirement
      org3 = create(:organization, admin: @owner)
      org3.add_member(@direct_member_with_2fa)
      org3.add_disallowed_two_factor_method(method: :sms, actor: @owner) if GitHub.two_factor_sms_enabled?
      GitHub.flipper[:enforce_disallow_two_factor_methods].disable(org3) # w/o enforcement, ignore disallowed methods

      results = @policy.multiple_two_factor_satisfied([@org, org2, org3], @target_provider)

      if GitHub.two_factor_sms_enabled?
        assert_equal :unsatisfied, results[@org][:private]
        assert_equal :satisfied, results[org3][:private]
      else
        assert_equal :satisfied, results[@org][:private]
        assert_equal :satisfied, results[org3][:private]
      end
      assert_equal :satisfied, results[org2][:private]
    end
  end

  context "#two_factor_satisfied" do
    context "disallowed methods feature flag disabled"  do
      test "returns no if 2FA disabled" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(false)
        assert_equal :no, @policy_user_no_2fa.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "returns yes if 2FA enabled" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(false)
        assert_equal :yes, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end
    end

    context "disallowed methods feature flag enabled"  do
      test "returns no if 2FA disabled" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        assert_equal :no, @policy_user_no_2fa.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "returns yes if no disallowed 2fa method policy set" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        assert_equal :yes, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "returns yes if user does not use a disallowed 2fa method" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        @org.add_disallowed_two_factor_method(method: :passkey, actor: @owner)
        assert_equal :yes, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "returns no if totp app configured but policy disallows it" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        @org.add_disallowed_two_factor_method(method: :totp, actor: @owner)

        assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      if GitHub.two_factor_sms_enabled?
        test "returns no if sms configured but policy disallows it" do
          @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
          @org.add_disallowed_two_factor_method(method: :sms, actor: @owner)

          assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
        end
      end

      test "returns no if security key configured but policy disallows it" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        @org.add_disallowed_two_factor_method(method: :security_key, actor: @owner)

        create(:security_key, user: @direct_member_with_2fa, nickname: "seckey")

        assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      test "returns no if passkey configured but policy disallows it" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
        @org.add_disallowed_two_factor_method(method: :passkey, actor: @owner)

        create(:trusted_device, user: @direct_member_with_2fa, nickname: "test_name")

        assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      end

      # This test can't be created until we define how to check if a user has mobile configured for 2FA.
      # This is a future problem but I want to leave this here as a reminder.
      # test "returns no if mobile configured but policy disallows it" do
      #   @org.stubs(:enforce_two_factor_methods_policy?).returns(true)
      #   @org.add_disallowed_two_factor_method(method: :gh_mobile, actor: @owner)

      #   assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
      # end

      test "raises error if invalid 2fa method used" do
        @org.stubs(:enforce_two_factor_methods_policy?).returns(true)

        # Since this test would catch someone adding a new method in the configurable but not the policy
        # a stub is needed to simulate that method being returned from the configurable
        methods = Set.new
        methods << :dummy_method
        Organization.any_instance.stubs(:get_two_factor_disallowed_methods).returns(methods)

        assert_raises Configurable::TwoFactorDisallowedMethods::InvalidTwoFactorMethod do
          @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
        end
      end
    end
  end
end
