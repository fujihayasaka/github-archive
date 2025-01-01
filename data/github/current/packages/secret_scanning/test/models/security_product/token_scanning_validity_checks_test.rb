# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningValidityChecksTest < GitHub::IntegrationTestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers
  include TurboghasHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    biz = create(:global_business)
    @user = create(:verified_user)
    @org = create(:organization, business: biz, admin: @user)
    # There is a setting that will cause token scanning to be enabled when advanced security is enabled,
    # so we should probably explicitly set that to false to be safe.
    SecretScanning::Features::Org::TokenScanning.new(@org).disable_secret_scanning_for_new_repos(actor: @user)

    @repo = create(:private_repository, owner: @org)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    @token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    @validity_checks_service = SecurityProduct::TokenScanningValidityChecks.new(@repo)
    @service_manager = SecurityProduct::ServiceManager.new(@repo)
    @advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
    self.enable_token_scanning
  end

  test "disabled by default" do
    refute @validity_checks_service.enabled?
  end

  test "if token scanning is enabled, then we can enable validity checks", skip_enterprise: true do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_validity_checks])
    refute err
    assert @validity_checks_service.enabled?
  end

  test "disabling token scanning disables validity checks" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_validity_checks])
    refute err
    assert @validity_checks_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning])
    refute err
    refute @token_scanning_service.enabled?

    refute @validity_checks_service.enabled?
  end

  test "disable validity checks" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_validity_checks])
    refute err
    assert @validity_checks_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_validity_checks])
    refute err
    refute @validity_checks_service.enabled?
  end

  context "can_enable" do
    test "returns false when secret scanning isn't enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @validity_checks_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_disabled
    end

    test "returns false when blocked by policy" do
      # Calling `feature_enabled?` caches the value on the instance.
      # In the test setup for this file, `self.enable_token_scanning` is called, which ultimately calls `feature_enabled?`
      # and sets the cache for our feature flag on the business to whatever the global value is for the flag (false by default, true in all features CI runs).
      # Calling `enable_feature` here will not clear the cached value on the object,
      # so we need to stub `feature_enabled?` instead to override the cache and "enable" the flag.
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)

      can_enable, error = @validity_checks_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if validity checks can be enabled" do
      can_enable, error = @validity_checks_service.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "can_disable" do
    test "returns false when blocked by policy" do
      # Calling `feature_enabled?` caches the value on the instance.
      # In the test setup for this file, `self.enable_token_scanning` is called, which ultimately calls `feature_enabled?`
      # and sets the cache for our feature flag on the business to whatever the global value is for the flag (false by default, true in all features CI runs).
      # Calling `enable_feature` here will not clear the cached value on the object,
      # so we need to stub `feature_enabled?` instead to override the cache and "disable" the flag.
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)

      can_disable, error = @validity_checks_service.can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if validity checks can be disabled" do
      can_disable, error = @validity_checks_service.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  test "publishes token_scanning_service.v0.EnablementChange" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_validity_checks])
    refute err
    assert @validity_checks_service.enabled?

    assert_hydro_published({
      repository_id: @repo.id,
      owner_id: @repo.owner_id,
      owner_scope: :ORGANIZATION_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      validity_checks: true
    }, schema: "token_scanning_service.v0.EnablementChange")

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_validity_checks])
    refute err
    refute @validity_checks_service.enabled?

    assert_hydro_published({
      repository_id: @repo.id,
      owner_id: @repo.owner_id,
      owner_scope: :ORGANIZATION_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      validity_checks: false
    }, schema: "token_scanning_service.v0.EnablementChange")
  end

  test "emits event in audit log when repository validation checks are enabled" do
    event_name = "repository_secret_scanning_automatic_validity_checks.enabled"
    events = assert_performed_audit_entries(count: 1, only: event_name) do
      _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_validity_checks])
      refute err
      assert @validity_checks_service.enabled?
    end

    assert_equal last_performed_audit_entries, events

    expected_payload  = {
      action: event_name,
      user: @user.login,
      repo: @repo.full_name,
      org: @repo.organization.login
    }

    assert_subset_hash expected_payload, events.first
  end

  test "emits event in audit log when repository validation checks are disabled" do
    event_name = "repository_secret_scanning_automatic_validity_checks.disabled"
    events = assert_performed_audit_entries(count: 1, only: event_name) do
      _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_validity_checks])
      refute err
      refute @validity_checks_service.enabled?
    end

    assert_equal last_performed_audit_entries, events

    expected_payload = {
      action: event_name,
      user: @user.login,
      repo: @repo.full_name,
      org: @repo.organization.login
    }

    assert_subset_hash expected_payload, events.first
  end

  private

  def enable_token_scanning
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:advanced_security, :token_scanning])
    refute err
    assert @token_scanning_service.enabled?
  end
end
