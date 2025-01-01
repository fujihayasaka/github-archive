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

class ConditionalAccess::TestTwoFactorAuthnEnforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::Policy::TwoFactorAuthn

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  def conditional_access_policies
    [:two_factor]
  end
  alias :registered_policies :conditional_access_policies
  alias :authzd_science_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end
  alias :authzd_cap_actor :actor

  def anonymous?
    callback.send(:anonymous?)
  end

  def authzd_cap_request_attributes
    {}
  end
end

class MockCallback
  attr_reader :actor
  alias :actor_for_conditional_access :actor

  def initialize(actor: nil, anonymous: true)
    @actor = actor
    @anonymous = anonymous
  end

  def anonymous?
    @anonymous
  end

  def authzd_cap_request_attributes
    attrs = {}
    attrs["conditional.access.anonymous"] = anonymous?
    attrs
  end
end

class CapTwoFactorAuthnPolicyTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @org = create :business_plus_org, admin: @owner

    @business = create :business, owners: [@owner]
    @business_member = create :user
    @business.add_owner(@business_member, actor: @owner)
    @business.enable_two_factor_required(actor: @owner)

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
  end

  setup do
    @policy = TestTwoFactorAuthnPolicy.new(current_user: @direct_member_with_2fa)
    @policy_user_no_2fa = TestTwoFactorAuthnPolicy.new(current_user: @direct_member_without_2fa)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "test")

    # baseline assertions
    assert @org.member?(@direct_member_without_2fa)
    assert @business_member.is_business_member?(@business.id)
  end

  def assert_result(callback, resource, expected_result)
    enforcer = ConditionalAccess::TestTwoFactorAuthnEnforcer.new(callback)
    results = enforcer.evaluate_conditional_access_policies resource
    assert_equal 1, results.size
    assert_equal :two_factor, results.keys.first
    assert_equal expected_result, results.values.first
  end

  def assert_satisfied(callback, resource)
    assert_result(callback, resource, :satisfied)
  end

  def assert_unsatisfied(callback, resource)
    assert_result(callback, resource, :unsatisfied)
  end

  def assert_inapplicable(callback, resource)
    assert_result(callback, resource, :inapplicable)
  end

  context "#multiple_two_factor_satisfied" do
    test "analyzes correctly" do
      @org.add_disallowed_two_factor_method(method: :sms, actor: @owner) if GitHub.two_factor_sms_enabled?
      org2 = create(:organization, admin: @owner)
      org2.enable_two_factor_requirement(actor: @owner)
      org2.add_member(@direct_member_with_2fa) # basic 2FA requirement
      org3 = create(:organization, admin: @owner)
      org3.add_member(@direct_member_with_2fa)
      org3.add_disallowed_two_factor_method(method: :sms, actor: @owner) if GitHub.two_factor_sms_enabled?

      results = @policy.multiple_two_factor_satisfied([@org, org2, org3], @target_provider)

      if GitHub.two_factor_sms_enabled?
        assert_equal :unsatisfied, results[@org][:private]
        assert_equal :unsatisfied, results[org3][:private]
      else
        assert_equal :satisfied, results[@org][:private]
        assert_equal :satisfied, results[org3][:private]
      end
      assert_equal :satisfied, results[org2][:private]
    end

    test "analyzes correctly if not directly affiliated with org, only through associated business membership" do
      biz_org_1 = create :organization, admin: @owner, business: @business
      biz_org_1.add_disallowed_two_factor_method(method: :sms, actor: @owner) if GitHub.two_factor_sms_enabled?

      results = TestTwoFactorAuthnPolicy.new(current_user: @business_member).multiple_two_factor_satisfied([biz_org_1], @target_provider)

      # unsatisfied, regardless of feature flag
      assert_equal :unsatisfied, results[biz_org_1][:private]

      if GitHub.two_factor_sms_enabled?
        make_two_factor_credential_both_otp_methods(@business_member)
      else
        make_two_factor_credential(@business_member)
      end
      results = TestTwoFactorAuthnPolicy.new(current_user: @business_member).multiple_two_factor_satisfied([biz_org_1], @target_provider)

      # satisfied because the user meets the _business_ requirement of 2FA
      # and doesn't care about the org they aren't directly associated with
      assert_equal :satisfied, results[biz_org_1][:private]
    end
  end

  context "#two_factor_satisfied" do
    test "returns no if 2FA disabled" do
      callback = MockCallback.new(actor: @direct_member_without_2fa, anonymous: false)
      assert_unsatisfied(callback, @org)
    end

    test "returns yes if no disallowed 2fa method policy set" do
      callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
      assert_satisfied(callback, @org)
    end

    test "returns yes if user does not use a disallowed 2fa method" do
      @org.add_disallowed_two_factor_method(method: :passkey, actor: @owner)
      callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
      assert_satisfied(callback, @org)
    end

    test "returns no if totp app configured but policy disallows it" do
      @org.add_disallowed_two_factor_method(method: :totp, actor: @owner)
      callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
      assert_unsatisfied(callback, @org)
    end

    if GitHub.two_factor_sms_enabled?
      test "returns no if sms configured but policy disallows it" do
        @org.add_disallowed_two_factor_method(method: :sms, actor: @owner)
        callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
        assert_unsatisfied(callback, @org)
      end
    end

    test "returns no if security key configured but policy disallows it" do
      @org.add_disallowed_two_factor_method(method: :security_key, actor: @owner)

      create(:security_key, user: @direct_member_with_2fa, nickname: "seckey")
      callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
      assert_unsatisfied(callback, @org)
    end

    test "returns no if passkey configured but policy disallows it" do
      @org.add_disallowed_two_factor_method(method: :passkey, actor: @owner)

      create(:trusted_device, user: @direct_member_with_2fa, nickname: "test_name")
      callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
      assert_unsatisfied(callback, @org)
    end

    # This test can't be created until we define how to check if a user has mobile configured for 2FA.
    # This is a future problem but I want to leave this here as a reminder.
    # test "returns no if mobile configured but policy disallows it" do
    #   @org.add_disallowed_two_factor_method(method: :gh_mobile, actor: @owner)

    #   assert_equal :no, @policy.two_factor_satisfied(resource: @org, target_provider: @target_provider)
    # end

    test "raises error if invalid 2fa method used" do
      # We can't yet send the stub to Authzd, so skipping this test for now
      disable_feature_flag(:run_authzd_cap_experiment)

      # Since this test would catch someone adding a new method in the configurable but not the policy
      # a stub is needed to simulate that method being returned from the configurable
      methods = Set.new
      methods << :dummy_method
      Organization.any_instance.stubs(:get_two_factor_disallowed_methods).returns(methods)

      assert_raises Configurable::TwoFactorDisallowedMethods::InvalidTwoFactorMethod do
        callback = MockCallback.new(actor: @direct_member_with_2fa, anonymous: false)
        assert_unsatisfied(callback, @org)
      end
    end
  end
end
