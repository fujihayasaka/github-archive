
# typed: true
# frozen_string_literal: true

require "test_helper"

class TenantVerificationPolicyTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Web::TenantVerificationPolicy

  def conditional_access_policies
    [:tenant_verification]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end
end

class TenantVerificationTestController < ApplicationController
  def index
  end

  def target_for_conditional_access
    Business.find_by(slug: params[:slug])
  end

  def cap_enforcer
    @conditional_access_enforcer ||= TenantVerificationPolicyTestEnforcer.new(self)
  end
end

class TestTenantVerificationPolicy
  include ConditionalAccess::Policy::TenantVerification

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

class TenantVerificationTest < GitHub::IntegrationTestCase
  # skip_with_all_emus since this is a specific multi-tenant enterprise test
  skip_with_all_emus
  skip_enterprise

  fixtures do
    ENV["MULTI_TENANT_ENTERPRISE"] = "1"
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    @random_user = create(:user, skip_enterprise_managed_user: true)

    @emu_owner = create(:emu, :owner)
    @emu_biz = @emu_owner.enterprise_managed_business
    @emu = create(:emu, business: @emu_biz)
    @emu_org = create :enterprise_linked_organization, business: @emu_biz, admin: @emu
    @emu_repo = create(:private_repository, :minimal, owner: @emu_org)
  end

  setup_once do
    TestRoutes.draw do
      get "/index", to: "tenant_verification_test#index"
      post "/index", to: "tenant_verification_test#index"
    end
  end

  setup do
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
    set_multi_tenant_enterprise(@emu_biz)
  end

  context "unit tests" do
    test "not applicable for nil tenant" do
      policy = TestTenantVerificationPolicy.new
      GitHub::CurrentTenant.set nil
      refute GitHub::CurrentTenant.get
      assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    context "applicability for apps" do
      test "not applicable for internal gh app with capability" do
        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        policy = TestTenantVerificationPolicy.new
        policy.stubs(:actor).returns(dependabot)

        assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end

      test "not applicable for internal oauth app with capability" do
        internal_oauth_app = create(:github_importer_oauth_app)
        policy = TestTenantVerificationPolicy.new
        policy.stubs(:actor).returns(internal_oauth_app)

        assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end

      test "not applicable for synchronized integrations" do
        GitHub.flipper[:proxima_avatar_sync].enable

        synchronized_integration = create(:synchronized_integration)
        policy = TestTenantVerificationPolicy.new
        policy.stubs(:actor).returns(synchronized_integration)

        assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end

      test "not applicable for synchronized OAuth applications" do
        GitHub.flipper[:proxima_avatar_sync].enable

        synchronized_app = create(:synchronized_oauth_application)
        policy = TestTenantVerificationPolicy.new
        policy.stubs(:actor).returns(synchronized_app)

        assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end
    end

    test "satisfied for the same tenant" do
      policy = TestTenantVerificationPolicy.new

      assert_equal :yes, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(@emu)

      assert_equal :yes, policy.tenant_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied for an actor that belongs to a different tenant than the current tenant" do
      policy = TestTenantVerificationPolicy.new
      diff_emu = create(:emu)
      assert diff_emu.enterprise_managed_business != @emu_biz
      GitHub::CurrentTenant.set @emu_biz

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(diff_emu)

      assert_equal :yes, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :no, policy.tenant_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied for anonymous requests" do
      policy = TestTenantVerificationPolicy.new

      assert_equal :yes, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :no, policy.tenant_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for an admin actor" do
      policy = TestTenantVerificationPolicy.new
      admin = create(:user, :staff)
      GitHub::CurrentTenant.set @emu_biz

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(admin)

      assert_equal :no, policy.tenant_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end
  end

  context "404s" do
    test "when SSO redirect disabled" do
      @emu_biz.disable_sso_redirect(actor: @emu_owner)
      as @random_user
      get "/index", params: { slug: @emu_biz.slug }
      assert_response :not_found
    end

    test "when not a GET request" do
      @emu_biz.enable_sso_redirect(actor: @emu_owner)
      as @random_user
      set_multi_tenant_enterprise(@emu_biz)
      post "/index", params: { slug: @emu_biz.slug }
      assert_response :not_found
    end
  end

  context "redirects" do
    test "when GET request and SSO redirect enabled" do
      @emu_biz.enable_sso_redirect(actor: @emu_owner)
      as @random_user
      set_multi_tenant_enterprise(@emu_biz)
      get "/index", params: { slug: @emu_biz.slug }
      assert_redirected_to_login(return_to: "/index?slug=#{@emu_biz.slug}")
    end
  end
end
