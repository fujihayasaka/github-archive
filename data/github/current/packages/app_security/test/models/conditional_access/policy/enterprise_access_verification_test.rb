
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

  def actor_ip
    "127.0.0.1"
  end

  def anonymous?
    !@current_user
  end

  def authenticated_through_integration?
    @authenticated_through_integration
  end

  def business_security_header
    nil
  end
end

class EnterpriseAccessVerificationTest < GitHub::IntegrationTestCase
  # skip_in_multitenant_mode since this policy is not applicable in multi-tenant mode
  skip_in_multitenant_mode
  skip_enterprise

  fixtures do
    @random_user = create(:user, skip_enterprise_managed_user: true)

    @emu_owner = create(:emu, :owner)
    @emu_biz = @emu_owner.enterprise_managed_business
    @emu = create(:emu, business: @emu_biz)
    @emu_org = create :enterprise_linked_organization, business: @emu_biz, admin: @emu
    @emu_repo = create(:private_repository, :minimal, owner: @emu_org)
  end

  setup_once do
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
    ::TestRoutes.draw do
      get "/index", to: "enterprise_access_verification_test#index"
      post "/index", to: "enterprise_access_verification_test#index"
    end
  end

  setup do
    GitHub.flipper[:enterprise_access_verification_beta].enable(@emu_biz)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  context "unit tests" do
    test "not applicable when no business slug" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(nil)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for enterprise when FF disabled" do
      GitHub.flipper[:enterprise_access_verification_beta].disable(@emu_biz)

      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.slug)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable when enterprise was not found" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns("non-existent")

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable when enterprise was not found using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns("0")

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable when enterprise is not emu" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      business = create(:business, slug: "non-emu", skip_enterprise_managed_business: true)
      policy.stubs(:business_security_header).returns(business.slug)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable when enterprise is not emu business using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      business = create(:business, slug: "non-emu", skip_enterprise_managed_business: true)
      policy.stubs(:business_security_header).returns(business.id)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable for an EMU business using slug" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.slug)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable for an EMU business using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.id.to_s)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for an EMU business using business id when ff disabled" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      GitHub.flipper[:enterprise_access_verification_beta].disable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.id)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "applicable for an EMU business using business id when proxy_security_header_enabled enabled" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      GitHub.flipper[:enterprise_access_verification_beta].disable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      Business.any_instance.stubs(:proxy_security_header_enabled?).returns(true)
      policy.stubs(:business_security_header).returns(@emu_biz.id)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for a staff user" do
      @staff = create :employee
      policy = TestEnterpriseAccessVerificationPolicy.new(@staff)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    context "applicability for apps" do
      test "applicable for internal gh app with capability" do
        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

        policy.stubs(:business_security_header).returns(@emu_biz.slug)
        policy.stubs(:actor).returns(dependabot)

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end

      test "applicable for internal oauth app with capability" do
        internal_oauth_app = create(:github_importer_oauth_app)
        policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

        policy.stubs(:business_security_header).returns(@emu_biz.slug)
        policy.stubs(:actor).returns(internal_oauth_app)

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end
    end

    test "satisfied for the same enterprise" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.slug)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(@emu)

      assert_equal :yes, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied for an actor that does not belongs to a current enterprise" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      diff_emu = create(:emu)
      assert diff_emu.enterprise_managed_business != @emu_biz

      # requests require an actor, fake it
      policy.stubs(:business_security_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(diff_emu)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "satisfied for anonymous requests" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(true)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      assert_equal :yes, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "satisfied for the same enterprise using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.id.to_s)

      assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)

      # requests require an actor, fake it
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(@emu)

      assert_equal :yes, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied when enterprise was not found" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns("non-existent")

      assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not satisfied  when enterprise was not found using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns("0")

      assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for an admin actor" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)
      admin = create(:user, :staff)

      # requests require an actor, fake it
      policy.stubs(:business_security_header).returns(@emu_biz.slug)
      policy.stubs(:anonymous_request?).returns(false)
      policy.stubs(:actor).returns(admin)

      assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
    end

    test "not applicable for multi-tenant" do
      policy = TestEnterpriseAccessVerificationPolicy.new(@emu)

      policy.stubs(:business_security_header).returns(@emu_biz.slug)

      on_multi_tenant_enterprise do
        assert_equal :no, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
      end
    end

    context "audit log" do
      test "business.proxy_security_header_unsatisfied event is emitted when not satisfied" do
        GitHub.flipper[:log_proxy_security_header_unsatisfied].enable(@emu_biz)

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        diff_emu = create(:emu)
        assert diff_emu.enterprise_managed_business != @emu_biz

        # pass the diff emu as the current user/actor
        policy = TestEnterpriseAccessVerificationPolicy.new(diff_emu)
        policy.stubs(:business_security_header).returns(@emu_biz.slug)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: diff_emu.display_login,
          actor_id: diff_emu.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
        assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event is not emitted when ff disabled" do
        GitHub.flipper[:log_proxy_security_header_unsatisfied].disable

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        diff_emu = create(:emu)
        assert diff_emu.enterprise_managed_business != @emu_biz

        # pass the diff emu as the current user/actor
        policy = TestEnterpriseAccessVerificationPolicy.new(diff_emu)
        policy.stubs(:business_security_header).returns(@emu_biz.slug)

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
        assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)

        refute events.pop, "no event expected"
      end

      test "business.proxy_security_header_unsatisfied event emitted when actor is Integration" do
        GitHub.flipper[:log_proxy_security_header_unsatisfied].enable(@emu_biz)

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        # pass dependabot as the current user/actor
        policy = TestEnterpriseAccessVerificationPolicy.new(dependabot)
        policy.stubs(:business_security_header).returns(@emu_biz.slug)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: dependabot.bot.display_login,
          actor_id: dependabot.bot.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
        assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event emitted when actor is IntegrationInstallation" do
        GitHub.flipper[:log_proxy_security_header_unsatisfied].enable(@emu_biz)

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        org = create(:organization)
        repo = create(:repository, owner: org)
        integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
        installation = make_integration_installation(integration: integration, repository: repo, target: org, permissions: { "metadata" => :read, "contents" => :write })

        # pass the installation as the current user/actor
        policy = TestEnterpriseAccessVerificationPolicy.new(installation)
        policy.stubs(:business_security_header).returns(@emu_biz.slug)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: installation.integration.bot.display_login,
          actor_id: installation.integration.bot.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
        assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event emitted when authenticated_key is PublicKey" do
        GitHub.flipper[:log_proxy_security_header_unsatisfied].enable(@emu_biz)

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        other_emu = create(:emu)
        other_biz = other_emu.enterprise_managed_business
        org = create(:organization, business: other_biz)
        repo = create(:repository, owner: org)
        public_key = create(:public_key, repository: repo)

        policy = TestEnterpriseAccessVerificationPolicy.new(nil, true)

        # stub the public key value, actor is nil
        policy.stubs(:business_security_header).returns(@emu_biz.slug)
        policy.stubs(:authenticated_key).returns(public_key)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: public_key.repository.owner.display_login,
          actor_id: public_key.repository.owner.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_equal :yes, policy.enterprise_access_verification_applicable(resource: @emu_repo, target_provider: @target_provider)
        assert_equal :no, policy.enterprise_access_verification_satisfied(resource: @emu_repo, target_provider: @target_provider)

        event = events.pop
        assert_equal expected_payload, event.payload
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

    test "for non existent business using business id" do
      GitHub.flipper[:enterprise_access_verification_public_beta].enable
      as @emu
      post "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => "0" }
      assert_response :bad_request

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(nil, "0"), body["error"]
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
