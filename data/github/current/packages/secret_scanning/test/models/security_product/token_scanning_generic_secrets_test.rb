# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningGenericSecretsTest < GitHub::IntegrationTestCase
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
    @generic_secrets_service = SecurityProduct::TokenScanningGenericSecrets.new(@repo)
    @service_manager = SecurityProduct::ServiceManager.new(@repo)
    @advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
    self.enable_token_scanning
  end

  test "disabled by default" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    refute @generic_secrets_service.enabled?
  end

  test "if token scanning is enabled, then we can enable generic secrets", skip_enterprise: true do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])
    refute err
    assert @generic_secrets_service.enabled?
  end

  test "disabling token scanning disables generic secrets" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])
    refute err
    assert @generic_secrets_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning])
    refute err
    refute @token_scanning_service.enabled?

    refute @generic_secrets_service.enabled?
  end

  test "disable generic_secrets" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])
    refute err
    assert @generic_secrets_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_generic_secrets])
    refute err
    refute @generic_secrets_service.enabled?
  end

  context "can_enable" do
    test "returns false when secret scanning isn't enabled" do
      SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @generic_secrets_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_disabled
    end

    test "returns false when blocked by policy" do
      Business.any_instance.stubs(:repo_admins_can_modify_generic_secrets_settings?).returns(false)

      can_enable, error = @generic_secrets_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if generic secrets can be enabled" do
      Business.any_instance.stubs(:repo_admins_can_modify_generic_secrets_settings?).returns(true)
      can_enable, error = @generic_secrets_service.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "can_disable" do
    test "returns false when blocked by policy" do
      Business.any_instance.stubs(:repo_admins_can_modify_generic_secrets_settings?).returns(false)

      can_disable, error = @generic_secrets_service.can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if generic secrets can be disabled" do
      Business.any_instance.stubs(:repo_admins_can_modify_generic_secrets_settings?).returns(true)
      can_disable, error = @generic_secrets_service.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  test "publishes token_scanning_service.v0.EnablementChange" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])
    refute err
    assert @generic_secrets_service.enabled?

    assert_hydro_published({
      repository_id: @repo.id,
      owner_id: @repo.owner_id,
      owner_scope: :ORGANIZATION_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      generic_secrets: true
    }, schema: "token_scanning_service.v0.EnablementChange")

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_generic_secrets])
    refute err
    refute @generic_secrets_service.enabled?

    assert_hydro_published({
      repository_id: @repo.id,
      owner_id: @repo.owner_id,
      owner_scope: :ORGANIZATION_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      generic_secrets: false
    }, schema: "token_scanning_service.v0.EnablementChange")
  end

  test "emits event in audit log when repository generic secrets are enabled" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    event_name = "repository_secret_scanning_generic_secrets.enabled"
    events = assert_performed_audit_entries(count: 1, only: event_name) do
      _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])
      refute err
      assert @generic_secrets_service.enabled?
    end

    assert_equal last_performed_audit_entries, events

    expected_payload  = {
      action: event_name,
      actor: @user.login,
      repo: @repo.full_name,
      org: @repo.organization.login
    }

    assert_subset_hash expected_payload, events.first
  end

  test "emits event in audit log when repository generic secrets are disabled" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)

    event_name = "repository_secret_scanning_generic_secrets.disabled"
    events = assert_performed_audit_entries(count: 1, only: event_name) do
      _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_generic_secrets])
      refute err
      refute @generic_secrets_service.enabled?
    end

    assert_equal last_performed_audit_entries, events

    expected_payload = {
      action: event_name,
      actor: @user.login,
      repo: @repo.full_name,
      org: @repo.organization.login
    }

    assert_subset_hash expected_payload, events.first
  end

  test "we emit a backfill request when enabling generic secrets" do
    SecurityProduct::TokenScanningGenericSecrets.any_instance.stubs(:blocked_by_enterprise_policy?).returns(false)
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    # does not automatically enable generic secrets
    refute @generic_secrets_service.enabled?

    # there's already a Hydro message due to enabling token scanning in setup
    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")

    # enable generic secrets
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_generic_secrets])

    # check stuff
    refute err
    assert @generic_secrets_service.enabled?
    assert_hydro_messages(count: 2, schema: "token_scanning_service.v0.BackfillRequest")
  end

  private

  def enable_token_scanning
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:advanced_security, :token_scanning])
    refute err
    assert @token_scanning_service.enabled?
  end
end
