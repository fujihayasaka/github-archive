
# typed: true
# frozen_string_literal: true

require "test_helper"

class TenantVerificationPolicyTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Web::TenantVerificationPolicy

  def initialize(callback, do_authzd_science: true)
    super(callback, do_authzd_science: do_authzd_science)
  end

  def conditional_access_policies
    [:tenant_verification]
  end
  alias :registered_policies :conditional_access_policies

  def authzd_science_policies
    [:tenant_verification]
  end

  def authzd_cap_actor
    actor
  end

  def authzd_cap_request_attributes
    {}
  end

  def location
    :test
  end

  def authenticated_through_integration?
    callback.send(:authenticated_through_integration?)
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

class TenantVerificationTest < GitHub::IntegrationTestCase
  # skip_with_all_emus since this is a specific multi-tenant enterprise test
  skip_with_all_emus
  skip_enterprise

  class MockCallback

    def initialize(actor = nil, authenticated_through_integration = false)
      @actor = actor
      @authenticated_through_integration = authenticated_through_integration
    end

    def current_user
      @actor
    end

    def logged_in?
      !!(@actor)
    end

    def anonymous?
      !@actor
    end

    def authenticated_through_integration?
      @authenticated_through_integration
    end
  end

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
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
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

  def assert_result(callback, resource, expected_result)
    enforcer = TenantVerificationPolicyTestEnforcer.new(callback)

    results = enforcer.evaluate_conditional_access_policies(resource)
    assert_equal 1, results.size
    assert_equal :tenant_verification, results.keys.first
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

  context "unit tests" do
    test "not applicable for nil tenant" do
      callback = MockCallback.new
      GitHub::CurrentTenant.set nil
      refute GitHub::CurrentTenant.get

      # we need to stub the response to the target_for_conditional_access since the nil tenant results in a nil owner
      if GitHub.flipper[:run_authzd_cap_experiment].enabled?
        @emu_repo.expects(:target_for_conditional_access).returns(@emu_biz)
      end
      assert_inapplicable(callback, @emu_repo)
    end

    context "applicability for apps" do
      test "not applicable for internal gh app with capability" do
        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        callback = MockCallback.new(dependabot)

        assert_inapplicable(callback, @emu_repo)
      end

      test "not applicable for internal oauth app with capability" do
        internal_oauth_app = create(:github_importer_oauth_app)

        callback = MockCallback.new(internal_oauth_app)

        assert_inapplicable(callback, @emu_repo)
      end

      test "not applicable for synchronized integrations" do
        enable_feature_flag(:proxima_avatar_sync)

        synchronized_integration = create(:synchronized_integration)

        callback = MockCallback.new(synchronized_integration)

        assert_inapplicable(callback, @emu_repo)
      end

      test "not applicable for synchronized OAuth applications" do
        enable_feature_flag(:proxima_avatar_sync)

        synchronized_app = create(:synchronized_oauth_application)
        callback = MockCallback.new(synchronized_app)

        assert_inapplicable(callback, @emu_repo)
      end
    end

    test "satisfied for the same tenant" do
      callback = MockCallback.new(@emu)
      assert_satisfied(callback, @emu_repo)
    end

    test "not satisfied for an actor that belongs to a different tenant than the current tenant" do
      diff_emu = create(:emu)
      assert diff_emu.enterprise_managed_business != @emu_biz
      GitHub::CurrentTenant.set @emu_biz
      callback = MockCallback.new(diff_emu)

      assert_unsatisfied(callback, @emu_repo)
    end

    test "not satisfied for anonymous requests" do
      callback = MockCallback.new
      assert_unsatisfied(callback, @emu_repo)
    end

    test "not applicable for an admin actor" do
      admin = create(:user, :staff)
      GitHub::CurrentTenant.set @emu_biz

      callback = MockCallback.new(admin)

      assert_inapplicable(callback, @emu_repo)
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
