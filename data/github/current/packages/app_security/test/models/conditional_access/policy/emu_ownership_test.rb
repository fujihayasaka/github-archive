
# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/policy_test_helper"
module EmuOwnershipTestHelpers
  class TestEmuEnforcer < ConditionalAccess::Api::Public::Enforcer
    def conditional_access_policies
      [:emu_ownership]
    end
    alias :registered_policies :conditional_access_policies

    def location
      :test
    end
  end

  class TestEmuFilter < ConditionalAccess::View::Filter
    def location
      :test
    end
  end

  class TestCallback
    attr_reader :actor
    alias :actor_for_conditional_access :actor
    alias :actor_for_conditional_access_authzd :actor
    alias :current_user :actor

    def initialize(actor: nil, get_request: false)
      @actor = actor
      @get_request = get_request
    end

    def anonymous?
      !@actor
    end

    def logged_in?
      !!@actor
    end

    def read_request?
      @get_request
    end
  end
end

class EmuOwnershipPolicyTest < GitHub::TestCase
  include EmuOwnershipTestHelpers
  include ConditionalAccess::PolicyTestHelpers
  skip_enterprise

  fixtures do
    @user = create(:user, skip_enterprise_managed_user: true)
    @emu = create(:emu)
    @emu_business = @emu.enterprise_managed_business
    @emu_business_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu

    @emu_repo = create(:private_repository, :minimal, owner: @emu_business_org)
  end

  setup do
    @enforcer_with_emu = TestEmuEnforcer.new(TestCallback.new(actor: @emu))
    @filter_with_emu = TestEmuFilter.new(TestCallback.new(actor: @emu))
  end

  def policy_name
    :emu_ownership
  end

  context "multiple applicable" do
    test "is applicable for EMU targets" do
      targets = [@emu_business, @emu_business, @emu]

      assert_filter(@filter_with_emu, targets, {
        @emu_business => :satisfied,
        @emu => :satisfied
      })
    end

    test "is inapplicable for non-EMU targets" do
      targets = [@emu_business, @emu_business, @emu]
      filter = TestEmuFilter.new(TestCallback.new(actor: @user))
      assert_filter(filter, targets, {
        @emu_business => :inapplicable,
        @emu => :inapplicable
      })
    end
  end

  context "multiple satisfied" do

    test "is satisfied for EMU targets" do
      targets = [@emu_business, @emu_business_org]
      assert_filter(@filter_with_emu, targets, {
        @emu_business => :satisfied,
        @emu_business_org => :satisfied,
      })
    end

    test "is only satisfied for EMU targets and unsatisfied for other targets" do
      org = create(:organization, skip_enterprise_managed_organization: true)
      business = create(:business_plus_org, skip_enterprise_managed_organization: true)

      targets = [@emu_business, org, @emu_business_org, business]
      assert_filter(@filter_with_emu, targets, {
        @emu_business => :satisfied,
        org => :unsatisfied,
        @emu_business_org => :satisfied,
        business => :unsatisfied
      })
    end
  end

  context "applicable" do
    test "Not applicable for non-EMU" do
      enforcer = TestEmuEnforcer.new(TestCallback.new(actor: @user))
      assert_inapplicable(enforcer, :no_resource_for_conditional_access)
    end

    test "Not applicable when no resource for conditional access" do
      assert_inapplicable(@enforcer_with_emu, :no_resource_for_conditional_access)
    end

    test "Applicable for programmatic actors" do
      integration = create(:integration, owner: @emu)
      installation = make_integration_installation(target: @emu_business_org, integration: integration, permissions: { "issues" => :write })
      # When making a server-to-server request, the current_user will be the bot
      enforcer = TestEmuEnforcer.new(TestCallback.new(actor: installation.bot))
      assert_satisfied(enforcer, @emu)
    end

    test "Applicable for EMU" do
      assert_satisfied(@enforcer_with_emu, @emu)
    end

    test "Not Applicable for anonymous user" do
      enforcer = TestEmuEnforcer.new(TestCallback.new(actor: nil))
      assert_inapplicable(enforcer, :no_target_for_conditional_access)
    end

    test "Return Applicable decision for GET" do
      enforcer = TestEmuEnforcer.new(TestCallback.new(actor: @emu, get_request: true))

      if TestEnv.test_in_multitenancy_mode?
        # on MultiTenant the policy is applicable so EMUs cannot browse public content like on dotcom
        assert_satisfied(enforcer, @emu_business)
      else
        assert_inapplicable(enforcer, @emu_business)
      end
    end

    test "Applicable for non GET" do
      enforcer = TestEmuEnforcer.new(TestCallback.new(actor: @emu, get_request: false))
      assert_satisfied(enforcer, @emu)
    end

    test "Not Applicable for the third party synced Apps in Proxima" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      # Third Party Synced Apps are owned by a special non-enterprise managed org
      # these apps should be visible to all tenants
      synced_app = create(:synchronized_integration)
      assert_inapplicable(@enforcer_with_emu, synced_app)
    end
  end

  context "satisfied" do
    test ":yes when target is EMU business" do
      assert_satisfied(@enforcer_with_emu, @emu_business)
    end

    if !GitHub.single_business_environment?
      test "returns only Business targets that are the EMU managing business" do
        business = create(:business, skip_enterprise_managed_business: true)
        assert_satisfied(@enforcer_with_emu, @emu_business)
        assert_unsatisfied(@enforcer_with_emu, business)
      end
    end

    test ":yes when target is Org within EMU business" do
      assert_satisfied(@enforcer_with_emu, @emu_repo)
    end

    test ":no for repository outside of EMU business" do
      org = create(:organization, skip_enterprise_managed_organization: true)
      repo = create(:repository, :minimal, owner: org)
      assert_unsatisfied(@enforcer_with_emu, repo)
    end

    test ":yes when target is the EMU itsef" do
      repo = create(:repository, :minimal, owner: @emu)
      assert_satisfied(@enforcer_with_emu, repo)
    end

    test ":no when the target is another user" do
      # for the moment we are not accounting for the TFCA
      # to be an EMU in the same business as the actor
      repo = create(:repository, :minimal, owner: @user)
      assert_unsatisfied(@enforcer_with_emu, repo)
    end

    unless GitHub.single_business_environment?
      test ":no when the target is EMU from a different enterprise" do
        another_emu = create(:emu)
        repo = create(:repository, :minimal, owner: another_emu)
        assert_unsatisfied(@enforcer_with_emu, repo)
      end


      test ":yes when the target is EMU from the same enterprise" do
        emu_in_same_business = create(:emu, business: @emu_business)
        repo = create(:repository, :minimal, owner: emu_in_same_business)
        assert_satisfied(@enforcer_with_emu, repo)
      end
    end
  end
end

class EnterpriseEmuOwnershipPolicyTest < GitHub::TestCase
  include EmuOwnershipTestHelpers
  include ConditionalAccess::PolicyTestHelpers

  skip_unless :single_business_environment?

  def policy_name
    :emu_ownership
  end

  test "is inapplicable on enterprise" do
    GitHub::Enterprise.ensure_business!
    enforcer = TestEmuEnforcer.new(TestCallback.new(actor: create(:user)))
    assert_inapplicable(enforcer, GitHub.global_business)
  end
end
