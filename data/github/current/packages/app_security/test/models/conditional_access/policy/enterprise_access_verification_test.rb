
# typed: true
# frozen_string_literal: true

require "test_helper"


class EnterpriseAccessVerificationPolicyIntegrationTestEnforcer < ConditionalAccess::Enforcer
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

class EnterpriseAccessVerificationPolicyTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::EnterpriseAccessVerificationPolicy

  def conditional_access_policies
    [:enterprise_access_verification]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def actor_ip
    callback.send(:actor_ip)
  end

  def repository
    callback.send(:repository)
  end

  def action
    callback.send(:action)
  end

  def request_access_security_header
    callback.send(:request_access_security_header)
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_through_integration?
    callback.send(:authenticated_through_integration?)
  end

  def anonymous?
    callback.send(:anonymous?)
  end
end

class EnterpriseAccessVerificationPolicyIntegrationTestAuthzdEnforcer < ConditionalAccess::AuthzdEnforcer
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Web::EnterpriseAccessVerificationPolicy

  def conditional_access_policies
    [:enterprise_access_verification]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def authzd_cap_actor
    actor
  end

  def authzd_cap_request_attributes
    attrs = {}
    if anonymous?
      attrs["conditional.access.anonymous"] = true
    end

    if authenticated_through_integration?
      attrs["conditional.access.authenticated_through_integration"] = true
    end

    if request_access_security_header
      attrs["conditional.access.request_access_security_header"] = request_access_security_header.to_s
    end

    if repository
      attrs["conditional.access.repository_id"] = repository.id
    end

    if authenticated_key
      attrs["conditional.access.authenticated_key_id"] = authenticated_key.id
    end

    attrs
  end
end

class EnterpriseAccessVerificationPolicyTestAuthzdEnforcer < ConditionalAccess::AuthzdEnforcer
  include ConditionalAccess::Web::EnterpriseAccessVerificationPolicy

  def conditional_access_policies
    [:enterprise_access_verification]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def actor_ip
    callback.send(:actor_ip)
  end

  def repository
    callback.send(:repository)
  end

  def action
    callback.send(:action)
  end

  def request_access_security_header
    callback.send(:request_access_security_header)
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_through_integration?
    callback.send(:authenticated_through_integration?)
  end

  def anonymous?
    callback.send(:anonymous?)
  end

  def authzd_cap_actor
    actor
  end

  def authzd_cap_request_attributes
    attrs = {}

    if anonymous?
      attrs["conditional.access.anonymous"] = true
    end

    if authenticated_through_integration?
      attrs["conditional.access.authenticated_through_integration"] = true
    end

    if request_access_security_header
      attrs["conditional.access.request_access_security_header"] = request_access_security_header.to_s
    end

    if repository
      attrs["conditional.access.repository_id"] = repository.id
    end

    if authenticated_key
      attrs["conditional.access.authenticated_key_id"] = authenticated_key.id
    end

    attrs
  end
end

class EnterpriseAccessVerificationTestController < ApplicationController
  def index
  end

  def target_for_conditional_access
    Business.find_by(slug: params[:slug])
  end

  def authenticated_key
    nil
  end

  def cap_enforcer
    @conditional_access_enforcer ||= ENV["TEST_CAP_VIA_AUTHZD"] == "1" ? EnterpriseAccessVerificationPolicyIntegrationTestAuthzdEnforcer.new(self) : EnterpriseAccessVerificationPolicyIntegrationTestEnforcer.new(self)
  end
end

class TestEnterpriseAccessVerificationCallback
  def initialize(
    repository: nil,
    actor: nil,
    authenticated_through_integration: false,
    request_access_security_header: nil,
    authenticated_key: nil,
    anonymous: false
  )
    @repository = repository
    @actor = actor
    @authenticated_through_integration = authenticated_through_integration
    @request_access_security_header = request_access_security_header
    @authenticated_key = authenticated_key
  end

  def actor_ip
    "127.0.0.1"
  end

  def repository
    @repository
  end

  def actor
    @actor
  end

  def anonymous?
    !@actor && !@authenticated_key
  end

  def authenticated_through_integration?
    !!@authenticated_through_integration
  end

  def request_access_security_header
    @request_access_security_header
  end

  def authenticated_key
    @authenticated_key
  end
end

class TestEnterpriseAccessVerificationResource
  def initialize(
    target: nil
  )
    @target = target
  end

  def target_for_conditional_access
    @target || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end

class EnterpriseAccessVerificationTest < GitHub::IntegrationTestCase
  # skip_in_multitenant_mode since this policy is not applicable in multi-tenant mode
  skip_in_multitenant_mode
  skip_enterprise

  fixtures do
    @employee = create(:employee)
    @random_user = create(:user, skip_enterprise_managed_user: true)

    @emu_owner = create(:emu, :owner)
    @emu_biz = @emu_owner.enterprise_managed_business
    @emu = create(:emu, business: @emu_biz)
    @emu_org = create :enterprise_linked_organization, business: @emu_biz, admin: @emu
    @emu_repo = create(:private_repository, :minimal, owner: @emu_org)
  end

  setup_once do
    ::TestRoutes.draw do
      get "/index", to: "enterprise_access_verification_test#index"
      post "/index", to: "enterprise_access_verification_test#index"
    end
  end

  setup do
    @emu_biz.enable_proxy_security_header(actor: @employee)
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
  end

  def assert_result(callback, resource, expected_result)
    enforcer = ENV["TEST_CAP_VIA_AUTHZD"] == "1" ? EnterpriseAccessVerificationPolicyTestAuthzdEnforcer.new(callback) : EnterpriseAccessVerificationPolicyTestEnforcer.new(callback)
    results = enforcer.evaluate_conditional_access_policies resource
    assert_equal 1, results.size
    assert_equal :enterprise_access_verification, results.keys.first
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

  context "direct policy tests" do
    test "not applicable when no business slug" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: nil)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_inapplicable(callback, resource)
    end

    test "not applicable for enterprise when proxy security header configurable is disabled" do
      @emu_biz.disable_proxy_security_header(actor: @employee)

      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_inapplicable(callback, resource)
    end

    test "applicable when enterprise was not found" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: "non-existent")
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_unsatisfied(callback, resource)
    end

    test "applicable when enterprise was not found using business id" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: "0")
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_unsatisfied(callback, resource)
    end

    test "not applicable when enterprise is not emu" do
      business = create(:business, slug: "non-emu", skip_enterprise_managed_business: true)
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: business.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_inapplicable(callback, resource)
    end

    test "not applicable when enterprise is not emu business using business id" do
      business = create(:business, slug: "non-emu", skip_enterprise_managed_business: true)
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: business.id)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_inapplicable(callback, resource)
    end

    test "applicable for an EMU business using slug" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_satisfied(callback, resource)
    end

    test "applicable for an EMU business using business id" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.id)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_satisfied(callback, resource)
    end

    test "not applicable for an EMU business using business id when proxy security header is disabled" do
      @emu_biz.disable_proxy_security_header(actor: @employee)

      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.id)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_inapplicable(callback, resource)
    end

    test "applicable for an EMU business using business id when proxy security header is enabled" do
      assert @emu_biz.proxy_security_header_enabled?

      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.id)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_satisfied(callback, resource)
    end

    test "not applicable for a staff user" do
      @staff = create :staff_admin_user
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @staff, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_inapplicable(callback, resource)
    end

    context "applicability for apps" do
      test "applicable for internal gh app with capability" do
        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        callback = TestEnterpriseAccessVerificationCallback.new(actor: dependabot, request_access_security_header: @emu_biz.slug)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        assert_unsatisfied(callback, resource)
      end

      test "applicable for internal oauth app with capability" do
        internal_oauth_app = create(:github_importer_oauth_app)

        callback = TestEnterpriseAccessVerificationCallback.new(actor: internal_oauth_app, request_access_security_header: @emu_biz.slug)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        # it makes it past applicable, but fails business_for(internal_oauth_app) with "unsupported target for conditional access: OauthApplication"
        if ENV["TEST_CAP_VIA_AUTHZD"] == "1"
          # improving coverage through authzd :flex:
          assert_unsatisfied(callback, resource)
        else
          assert_raises(ArgumentError) { assert_unsatisfied(callback, resource) }
        end
      end
    end

    test "satisfied for the same enterprise" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_satisfied(callback, resource)
    end

    test "not satisfied for an actor that does not belongs to a current enterprise" do
      diff_emu = create(:emu)
      assert diff_emu.enterprise_managed_business != @emu_biz

      callback = TestEnterpriseAccessVerificationCallback.new(actor: diff_emu, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_unsatisfied(callback, resource)
    end

    test "satisfied for anonymous requests" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: nil, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_satisfied(callback, resource)
    end

    test "satisfied for the same enterprise using business id" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.id)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_satisfied(callback, resource)
    end

    test "not satisfied when enterprise was not found" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: "non-existent")
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)
      assert_unsatisfied(callback, resource)
    end

    test "not satisfied when enterprise was not found using business id" do
      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: "0")
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_unsatisfied(callback, resource)
    end

    test "not applicable for an admin actor" do
      admin = create(:user, :staff)

      callback = TestEnterpriseAccessVerificationCallback.new(actor: admin, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      assert_inapplicable(callback, resource)
    end

    test "not applicable for multi-tenant" do
      # we can't easily tell authzd we are running in multi-tenant mode, so we need to skip this test if we are using authzd
      skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

      callback = TestEnterpriseAccessVerificationCallback.new(actor: @emu, request_access_security_header: @emu_biz.slug)
      resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

      on_multi_tenant_enterprise do
        assert_inapplicable(callback, resource)
      end
    end

    context "audit log" do
      test "business.proxy_security_header_unsatisfied event is emitted when not satisfied" do
        # aren't emitting the events in authzd yet, and even if we were, I'm not sure if we'd be able to assert them here easily
        skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        diff_emu = create(:emu)
        assert diff_emu.enterprise_managed_business != @emu_biz

        callback = TestEnterpriseAccessVerificationCallback.new(actor: diff_emu, request_access_security_header: @emu_biz.slug)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: diff_emu.display_login,
          actor_id: diff_emu.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_unsatisfied(callback, resource)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event emitted when actor is Integration" do
        # aren't emitting the events in authzd yet, and even if we were, I'm not sure if we'd be able to assert them here easily
        skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        Apps::Privileged::Registry.reset_configuration!
        make_trusted_oauth_apps_owner
        dependabot = create(:dependabot_integration)

        callback = TestEnterpriseAccessVerificationCallback.new(actor: dependabot, request_access_security_header: @emu_biz.slug)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: dependabot.bot.display_login,
          actor_id: dependabot.bot.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_unsatisfied(callback, resource)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event emitted when actor is Bot via IntegrationInstallation" do
        # aren't emitting the events in authzd yet, and even if we were, I'm not sure if we'd be able to assert them here easily
        skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        org = create(:organization)
        repo = create(:repository, owner: org)
        integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
        installation = make_integration_installation(integration: integration, repository: repo, target: org, permissions: { "metadata" => :read, "contents" => :write })
        bot = installation.bot

        callback = TestEnterpriseAccessVerificationCallback.new(actor: bot, request_access_security_header: @emu_biz.slug)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: installation.integration.bot.display_login,
          actor_id: installation.integration.bot.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_unsatisfied(callback, resource)

        event = events.pop
        assert_equal expected_payload, event.payload
      end

      test "business.proxy_security_header_unsatisfied event emitted when authenticated_key is PublicKey" do
        # aren't emitting the events in authzd yet, and even if we were, I'm not sure if we'd be able to assert them here easily
        skip if ENV["TEST_CAP_VIA_AUTHZD"] == "1"

        events = subscribe "business.#{ConditionalAccess::Policy::EnterpriseAccessVerification::PROXY_SECURITY_HEADER_UNSATISFIED}"

        other_emu = create(:emu)
        other_biz = other_emu.enterprise_managed_business
        org = create(:organization, business: other_biz)
        repo = create(:repository, owner: org)
        public_key = create(:public_key, repository: repo)

        callback = TestEnterpriseAccessVerificationCallback.new(actor: nil, request_access_security_header: @emu_biz.slug, authenticated_key: public_key, repository: repo)
        resource = TestEnterpriseAccessVerificationResource.new(target: @emu_repo.owner)

        expected_payload = {
          business: @emu_biz.slug,
          business_id: @emu_biz.id,
          actor: public_key.repository.owner.display_login,
          actor_id: public_key.repository.owner.id,
          actor_ip: "127.0.0.1",
          name: @emu_biz.name,
        }

        assert_unsatisfied(callback, resource)

        event = events.pop
        assert_equal expected_payload, event.payload
      end
    end
  end

  context "controller integration 403s" do
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

  context "controller integration 400s" do
    test "for non existent business" do
      as @emu
      post "/index", params: { slug: @emu_biz.slug }, headers: { "sec-GitHub-allowed-enterprise" => "non-existent" }
      assert_response :bad_request

      body = JSON.parse(response.body)
      assert_equal ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(nil, "non-existent"), body["error"]
    end

    test "for non existent business using business id" do
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
