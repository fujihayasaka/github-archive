
# typed: true
# frozen_string_literal: true

require "test_helper"

class TestEmuVisibilityPolicy
  include ConditionalAccess::Policy::EmuVisibility

  def initialize(current_user = nil, authenticated_through_integration = false)
    @current_user = current_user
    @authenticated_through_integration = authenticated_through_integration
  end

  def actor
    @current_user
  end

  def anonymous?
    !@current_user
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

  context "not applicable" do
    test "for :no_target_for_conditional_access" do
      policy = TestEmuVisibilityPolicy.new
      assert_equal :no, policy.emu_visibility_applicable(resource: :no_resource_for_conditional_access, target_provider: @target_provider)
    end

    test "for regular business target" do
      policy = TestEmuVisibilityPolicy.new
      biz = create(:business, skip_enterprise_managed_business: true)
      assert_equal :no, policy.emu_visibility_applicable(resource: biz, target_provider: @target_provider)
    end

    test "for regular org target" do
      policy = TestEmuVisibilityPolicy.new
      org = create(:business_plus_organization, skip_enterprise_managed_organization: true)
      assert_equal :no, policy.emu_visibility_applicable(resource: org, target_provider: @target_provider)
    end

    test "for regular user target" do
      policy = TestEmuVisibilityPolicy.new
      user = create(:user, skip_enterprise_managed_user: true)
      assert_equal :no, policy.emu_visibility_applicable(resource: user, target_provider: @target_provider)
    end

    test "for site admins" do
      policy = TestEmuVisibilityPolicy.new
      staff = create(:user, :staff)
      assert_equal :no, policy.emu_visibility_applicable(resource: staff, target_provider: @target_provider)
    end

    test "for the third party synced Apps in Proxima" do
      policy = TestEmuVisibilityPolicy.new
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      # Third Party Synced Apps are owned by a special non-enterprise managed org
      # these apps should be visible to all tenants
      synced_app = create(:synchronized_integration)
      assert_equal :no, policy.emu_visibility_applicable(resource: synced_app, target_provider: @target_provider)
    end
  end

  context "applicable" do
    test "for EMU business target" do
      policy = TestEmuVisibilityPolicy.new
      assert_equal :yes, policy.emu_visibility_applicable(resource: @emu_biz, target_provider: @target_provider)
    end

    test "for EMU org target" do
      policy = TestEmuVisibilityPolicy.new
      assert_equal :yes, policy.emu_visibility_applicable(resource: @emu_org, target_provider: @target_provider)
    end

    test "for EMU user target" do
      policy = TestEmuVisibilityPolicy.new
      assert_equal :yes, policy.emu_visibility_applicable(resource: @emu, target_provider: @target_provider)
    end
  end

  context "not satisfied" do
    test "for anonymous actors" do
      policy = TestEmuVisibilityPolicy.new
      assert_equal :no, policy.emu_visibility_satisfied(resource: @emu_org, target_provider: @target_provider)
    end

    test "for regular users without a business" do
      policy = TestEmuVisibilityPolicy.new(create(:user, skip_enterprise_managed_user: true))
      assert_equal :no, policy.emu_visibility_satisfied(resource: @emu_org, target_provider: @target_provider)
    end

    test "for regular users belonging to another business" do
      biz = create(:business, skip_enterprise_managed_business: true)
      policy = TestEmuVisibilityPolicy.new(biz.admins.first)
      assert_equal :no, policy.emu_visibility_satisfied(resource: @emu_org, target_provider: @target_provider)
    end

    test "for EMU users belonging to another enterprise" do
      policy = TestEmuVisibilityPolicy.new(create(:emu))
      assert_equal :no, policy.emu_visibility_satisfied(resource: @emu_org, target_provider: @target_provider)
    end
  end

  context "satisfied" do
    test "for EMU targetting a business owned resource in their enterprise" do
      policy = TestEmuVisibilityPolicy.new(@emu)
      assert_equal :yes, policy.emu_visibility_satisfied(resource: @emu_biz, target_provider: @target_provider)
    end

    test "for EMU targetting an org owned resource in their enterprise" do
      policy = TestEmuVisibilityPolicy.new(@emu)
      assert_equal :yes, policy.emu_visibility_satisfied(resource: @emu_org, target_provider: @target_provider)
    end

    test "for EMU targetting a user owned resource in their enterprise" do
      another_emu = create(:emu, business: @emu_biz)
      policy = TestEmuVisibilityPolicy.new(@emu)
      assert_equal :yes, policy.emu_visibility_satisfied(resource: another_emu, target_provider: @target_provider)
    end

    test "for EMU targetting their own resources" do
      policy = TestEmuVisibilityPolicy.new(@emu)
      assert_equal :yes, policy.emu_visibility_satisfied(resource: @emu, target_provider: @target_provider)
    end
  end
end
