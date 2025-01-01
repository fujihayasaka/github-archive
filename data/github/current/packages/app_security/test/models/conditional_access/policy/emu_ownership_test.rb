
# typed: true
# frozen_string_literal: true

require "test_helper"

class TestEmuPolicy
  include ConditionalAccess::Policy::EmuOwnership

  def initialize(current_user: nil, get_request: false)
    @current_user = current_user
    @get_request = get_request
  end

  def actor
    @current_user
  end

  def anonymous?
    !@current_user
  end

  def safe_request_method?
    @get_request
  end

  def location
    :test
  end

  def callback_name
    self.class.name
  end
end

class EmuOwnershipPolicyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @user = create(:user, skip_enterprise_managed_user: true)
    @emu = create(:emu)
    @emu_business = @emu.enterprise_managed_business
    @emu_business_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu

    @emu_repo = create(:private_repository, :minimal, owner: @emu_business_org)
  end

  setup do
    @policy_with_emu = TestEmuPolicy.new(current_user: @emu)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  context "multiple applicable" do
    test "is applicable for EMU targets" do
      assert_equal [@emu_business, @emu_business, @emu], @policy_with_emu.multiple_emu_ownership_applicable([@emu_business, @emu_business, @emu], @target_provider)
    end

    test "is inapplicable for non EMU targets" do
      policy = TestEmuPolicy.new(current_user: @user)
      assert_equal [], policy.multiple_emu_ownership_applicable([@emu_business, @emu_business, @emu], @target_provider)
    end
  end

  context "multiple satisfied" do
    test "is satisfied for EMU targets" do
      satisfied_targets_with_visibility = {
        @emu_business => { private: :satisfied },
        @emu_business_org => { private: :satisfied },
      }
      assert_equal satisfied_targets_with_visibility, @policy_with_emu.multiple_emu_ownership_satisfied(satisfied_targets_with_visibility.keys, @target_provider)
    end

    test "is only satisfied for EMU targets and unsatisfied for other targets" do
      org = create(:organization, skip_enterprise_managed_organization: true)
      business = create(:business_plus_org, skip_enterprise_managed_organization: true)

      targets_with_visibility = {
        @emu_business => { private: :satisfied },
        org => { private: :unsatisfied },
        @emu_business_org => { private: :satisfied },
      }
      assert_equal targets_with_visibility, @policy_with_emu.multiple_emu_ownership_satisfied(targets_with_visibility.keys, @target_provider)

      targets_with_visibility = {
        business => { private: :unsatisfied },
        org => { private: :unsatisfied },
      }
      assert_equal targets_with_visibility, @policy_with_emu.multiple_emu_ownership_satisfied(targets_with_visibility.keys, @target_provider)
    end
  end

  context "applicable" do
    test "Not applicable for non-EMU" do
      policy = TestEmuPolicy.new(current_user: @user)
      assert_equal :no, policy.emu_ownership_applicable(resource: :no_resource_for_conditional_access, target_provider: @target_provider)
    end

    test "Not applicable when no resource for conditional access" do
      assert_equal :no, @policy_with_emu.emu_ownership_applicable(resource: :no_resource_for_conditional_access, target_provider: @target_provider)
    end

    test "Applicable for programmatic actors" do
      integration = create(:integration, owner: @emu)
      installation = make_integration_installation(target: @emu_business_org, integration: integration, permissions: { "issues" => :write })
      # When making a server-to-server request, the current_user will be the bot
      policy = TestEmuPolicy.new(current_user: installation.bot)
      assert_equal :yes, policy.emu_ownership_applicable(resource: @emu, target_provider: @target_provider)
    end

    test "Applicable for EMU" do
      assert_equal :yes, @policy_with_emu.emu_ownership_applicable(resource: @emu, target_provider: @target_provider)
    end

    test "Not Applicable for anonymous user" do
      policy = TestEmuPolicy.new
      assert_equal :no, policy.emu_ownership_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
    end

    test "Return Applicable decision for GET" do
      policy_with_get = TestEmuPolicy.new(current_user: @emu, get_request: true)
      if TestEnv.test_in_multitenancy_mode?
        # on MultiTenant we do not allow EMUs to browse public content like on dotcom
        assert_equal :yes, policy_with_get.emu_ownership_applicable(resource: @emu_business, target_provider: @target_provider)
      else
        assert_equal :no, policy_with_get.emu_ownership_applicable(resource: @emu_business, target_provider: @target_provider)
      end
    end

    test "Applicable for non GET" do
      policy_with_non_get = TestEmuPolicy.new(current_user: @emu, get_request: false)
      assert_equal :yes, policy_with_non_get.emu_ownership_applicable(resource: @emu, target_provider: @target_provider)
    end

    test "Not Applicable for the third party synced Apps in Proxima" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      # Third Party Synced Apps are owned by a special non-enterprise managed org
      # these apps should be visible to all tenants
      synced_app = create(:synchronized_integration)
      assert_equal :no, @policy_with_emu.emu_ownership_applicable(resource: synced_app, target_provider: @target_provider)
    end
  end

  context "satisfied" do
    test ":yes when target is EMU business" do
      assert_equal :yes, @policy_with_emu.emu_ownership_satisfied(resource: @emu_business, target_provider: @target_provider)
    end

    if !GitHub.single_business_environment?
      test "returns only Business targets that are the EMU managing business" do
        business = create(:business, skip_enterprise_managed_business: true)
        assert_equal :yes, @policy_with_emu.emu_ownership_satisfied(resource: @emu_business, target_provider: @target_provider)
        assert_equal :no, @policy_with_emu.emu_ownership_satisfied(resource: business, target_provider: @target_provider)
      end
    end

    test ":yes when target is Org within EMU business" do
      assert_equal :yes, @policy_with_emu.emu_ownership_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test ":no for repository outside of EMU business" do
      org = create(:organization, skip_enterprise_managed_organization: true)
      repo = create(:repository, :minimal, owner: org)
      assert_equal :no, @policy_with_emu.emu_ownership_satisfied(resource: repo, target_provider: @target_provider)
    end

    test ":yes when target is the EMU itsef" do
      repo = create(:repository, :minimal, owner: @emu)
      assert_equal :yes, @policy_with_emu.emu_ownership_satisfied(resource: repo, target_provider: @target_provider)
    end

    test ":no when the target is another user" do
      # for the moment we are not accounting for the TFCA
      # to be an EMU in the same business as the actor
      repo = create(:repository, :minimal, owner: @user)
      assert_equal :no, @policy_with_emu.emu_ownership_satisfied(resource: repo, target_provider: @target_provider)
    end

    unless GitHub.single_business_environment?
      test ":no when the target is EMU from a different enterprise" do
        another_emu = create(:emu)
        repo = create(:repository, :minimal, owner: another_emu)
        assert_equal :no, @policy_with_emu.emu_ownership_satisfied(resource: repo, target_provider: @target_provider)
      end


      test ":yes when the target is EMU from the same enterprise" do
        emu_in_same_business = create(:emu, business: @emu_business)
        repo = create(:repository, :minimal, owner: emu_in_same_business)
        assert_equal :yes, @policy_with_emu.emu_ownership_satisfied(resource: repo, target_provider: @target_provider)
      end
    end
  end
end

class EnterpriseEmuOwnershipPolicyTest < GitHub::TestCase
  skip_unless :single_business_environment?

  fixtures do
    @user = create(:user)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  test "is inapplicable on enterprise" do
    policy = TestEmuPolicy.new(current_user: @user)
    assert_equal :no, policy.emu_ownership_applicable(resource: GitHub.global_business, target_provider: @target_provider)
  end
end
