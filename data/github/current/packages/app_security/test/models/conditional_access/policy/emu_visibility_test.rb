
# typed: true
# frozen_string_literal: true

require "test_helper"

class EmuVisibilityPolicyTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::EmuVisibilityPolicy

  def initialize(callback, do_authzd_science: true)
    super(callback, do_authzd_science: do_authzd_science)
  end

  def conditional_access_policies
    [:emu_visibility]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def authzd_science_policies
    [:emu_visibility]
  end

  def actor
    callback.send(:actor)
  end

  def anonymous?
    callback.send(:anonymous?)
  end

  def authenticated_through_integration?
    callback.send(:authenticated_through_integration?)
  end

  def authzd_cap_actor
    callback.send(:actor)
  end

  def authzd_cap_request_attributes
    attrs = {}
    if anonymous?
      attrs["conditional.access.anonymous"] = true
    end
    if authenticated_through_integration?
      attrs["conditional.access.authenticated_through_integration"] = true
    end
    attrs
  end
end

# Represents the callback object for the EmuVisibilityPolicy
class TestEmuVisibilityCallback
  def initialize(
    actor: nil,
    authenticated_through_integration: false
  )
    @actor = actor
    @authenticated_through_integration = authenticated_through_integration
  end

  def actor
    @actor
  end

  def anonymous?
    !@actor
  end

  def authenticated_through_integration?
    @authenticated_through_integration
  end
end

class EmuVisibilityPolicyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @emu = create(:emu)
    @emu_biz = @emu.enterprise_managed_business
    @emu_org = create :enterprise_linked_organization, business: @emu_biz, admin: @emu
    @emu_repo = create(:private_repository, :minimal, owner: @emu_org)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  def assert_result(callback, resource, result)
    enforcer = EmuVisibilityPolicyTestEnforcer.new(callback)
    results = enforcer.evaluate_conditional_access_policies resource
    assert_equal 1, results.size
    assert_equal :emu_visibility, results.keys.first
    assert_equal result, results.values.first
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

  context "not applicable" do
    test "for :no_target_for_conditional_access" do
      callback = TestEmuVisibilityCallback.new
      assert_inapplicable(callback, :no_resource_for_conditional_access)
    end

    test "for regular business target" do
      callback = TestEmuVisibilityCallback.new
      biz = create(:business, skip_enterprise_managed_business: true)
      assert_inapplicable(callback, biz)
    end

    test "for regular org target" do
      callback = TestEmuVisibilityCallback.new
      org = create(:business_plus_organization, skip_enterprise_managed_organization: true)
      assert_inapplicable(callback, org)
    end

    test "for regular user target" do
      callback = TestEmuVisibilityCallback.new
      user = create(:user, skip_enterprise_managed_user: true)
      assert_inapplicable(callback, user)
    end

    test "for site admins" do
      staff = create(:user, :staff)
      callback = TestEmuVisibilityCallback.new(actor: staff)
      assert_inapplicable(callback, staff)
    end

    test "for the third party synced Apps in Proxima" do
      callback = TestEmuVisibilityCallback.new
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      # Third Party Synced Apps are owned by a special non-enterprise managed org
      # these apps should be visible to all tenants
      synced_app = create(:synchronized_integration)
      assert_inapplicable(callback, synced_app)
    end
  end

  context "applicable" do
    test "for EMU business target" do
      callback = TestEmuVisibilityCallback.new
      # not satisfied means we made it past the applicable check (aka applicable)
      assert_unsatisfied(callback, @emu_biz)
    end

    test "for EMU org target" do
      callback = TestEmuVisibilityCallback.new
      # not satisfied means we made it past the applicable check (aka applicable)
      assert_unsatisfied(callback, @emu_org)
    end

    test "for EMU user target" do
      callback = TestEmuVisibilityCallback.new
      # not satisfied means we made it past the applicable check (aka applicable)
      assert_unsatisfied(callback, @emu)
    end
  end

  context "not satisfied" do
    test "for anonymous actors" do
      callback = TestEmuVisibilityCallback.new(actor: nil)
      assert_unsatisfied(callback, @emu_org)
    end

    test "for regular users without a business" do
      callback = TestEmuVisibilityCallback.new(actor: create(:user, skip_enterprise_managed_user: true))
      assert_unsatisfied(callback, @emu_org)
    end

    test "for regular users belonging to another business" do
      biz = create(:business, skip_enterprise_managed_business: true)
      callback = TestEmuVisibilityCallback.new(actor: biz.admins.first)
      assert_unsatisfied(callback, @emu_org)
    end

    test "for EMU users belonging to another enterprise" do
      callback = TestEmuVisibilityCallback.new(actor: create(:emu))
      assert_unsatisfied(callback, @emu_org)
    end
  end

  context "satisfied" do
    test "for EMU targetting a business owned resource in their enterprise" do
      callback = TestEmuVisibilityCallback.new(actor: @emu)
      assert_satisfied(callback, @emu_biz)
    end

    test "for EMU targetting an org owned resource in their enterprise" do
      callback = TestEmuVisibilityCallback.new(actor: @emu)
      assert_satisfied(callback, @emu_org)
    end

    test "for EMU targetting a user owned resource in their enterprise" do
      another_emu = create(:emu, business: @emu_biz)
      callback = TestEmuVisibilityCallback.new(actor: @emu)
      assert_satisfied(callback, another_emu)
    end

    test "for EMU targetting their own resources" do
      callback = TestEmuVisibilityCallback.new(actor: @emu)
      assert_satisfied(callback, @emu)
    end
  end
end
