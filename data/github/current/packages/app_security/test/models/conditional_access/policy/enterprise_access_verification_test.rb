
# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseAccessVerificationPolicyTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Web::EnterpriseAccessVerificationPolicy

  def conditional_access_policies
    [:enterprise_access_verification]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end
end

class EnterpriseAccessVerificationTestController < ApplicationController
  def index
  end

  def target_for_conditional_access
    Business.find_by(slug: params[:slug])
  end

  def cap_enforcer
    @conditional_access_enforcer ||= EnterpriseAccessVerificationPolicyTestEnforcer.new(self)
  end
end

class TestEnterpriseAccessVerificationPolicy
  include ConditionalAccess::Policy::EnterpriseAccessVerification

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

  def business_slug_header
    @business_slug_header
  end
end

class EnterpriseAccessVerificationTest < GitHub::IntegrationTestCase
  # skip_in_multitenant_mode since this policy is not applicable in multi-tenant mode
  skip_in_multitenant_mode
  skip_enterprise

  fixtures do
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
      get "/index", to: "enterprise_access_verification_test#index"
      post "/index", to: "enterprise_access_verification_test#index"
    end
  end

  setup do
    GitHub.flipper[:enterprise_access_verification_beta].enable(@emu_biz)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  context "unit tests" do
    test "not applicable for when no business slug" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns(nil)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for enterprise when FF disabled" do
      GitHub.flipper[:enterprise_access_verification_beta].disable(@emu_biz)

      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns(@emu_biz.slug)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable when enterprise was not found" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns("non-existent")

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable when enterprise is not emu" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      business = create(:business, slug: "non-emu", skip_enterprise_managed_business: true)
      policy.stubs(:business_slug_header).returns(business.slug)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    context "applicability for apps" do
      test "applicable for internal gh app with capability" do
        Apps::Internal::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        policy = TestEnterpriseAccessVerificationPolicy.new

        policy.stubs(:business_slug_header).returns(@emu_biz.slug)
        policy.stubs(:actor).returns(dependabot)

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end

      test "applicable for internal oauth app with capability" do
        internal_oauth_app = create(:github_importer_oauth_app)
        policy = TestEnterpriseAccessVerificationPolicy.new

        policy.stubs(:business_slug_header).returns(@emu_biz.slug)
        policy.stubs(:actor).returns(internal_oauth_app)

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end
    end

    test "satisfied for the same enterprise" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns(@emu_biz.slug)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(@emu)

      assert_equal :yes, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied for an actor that does not belongs to a current enterprise" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      diff_emu = create(:emu)
      assert diff_emu.enterprise_managed_business != @emu_biz

      # requests require an actor, fake it
      policy.stubs(:business_slug_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(diff_emu)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "satisfied for anonymous requests" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(true)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :yes, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for an admin actor" do
      policy = TestEnterpriseAccessVerificationPolicy.new
      admin = create(:user, :staff)

      # requests require an actor, fake it
      policy.stubs(:business_slug_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(admin)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for multi-tenant" do
      policy = TestEnterpriseAccessVerificationPolicy.new

      policy.stubs(:business_slug_header).returns(@emu_biz.slug)

      on_multi_tenant_enterprise do
        assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end
    end
  end

  context "403s" do
    test "for random user" do
      as @random_user
      get "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => @emu_biz.slug }
      assert_response :forbidden

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(@emu_biz, @emu_biz.slug), body["error"]
    end

    test "when not a GET request" do
      as @random_user
      post "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => @emu_biz.slug }
      assert_response :forbidden

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(@emu_biz, @emu_biz.slug), body["error"]
    end
  end

  context "400s" do
    test "for non existent business" do
      as @emu
      post "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => "non-existent" }
      assert_response :bad_request

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(nil, "non-existent"), body["error"]
    end

    test "for multiple slugs in a header" do
      as @emu
      post "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => "non-existent1,non-existent2" }
      assert_response :bad_request

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(nil, "non-existent1,non-existent2"), body["error"]
    end
  end
end
