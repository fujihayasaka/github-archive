# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningDelegatedBypassTest < GitHub::IntegrationTestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers
  include TurboghasHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
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
    @push_protection_service = SecurityProduct::TokenScanningPushProtection.new(@repo)
    @delegated_bypass_service = SecurityProduct::TokenScanningDelegatedBypass.new(@repo)
    @service_manager = SecurityProduct::ServiceManager.new(@repo)
    @advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:feature_available?).returns(true)
    self.enable_token_scanning
  end

  test "disabled by default" do
    refute @delegated_bypass_service.enabled?
  end

  test "if token scanning and push protection are enabled, then we can enable delegated bypass" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_bypass])
    refute err
    assert @delegated_bypass_service.enabled?
  end

  test "disabling token scanning disables delegated bypass" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_bypass])
    refute err
    assert @delegated_bypass_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning])
    refute err
    refute @token_scanning_service.enabled?

    refute @delegated_bypass_service.enabled?
  end

  test "disabling push protection disables delegated bypass" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_bypass])
    refute err
    assert @delegated_bypass_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_push_protection])
    refute err
    refute @push_protection_service.enabled?

    refute @delegated_bypass_service.enabled?
  end

  test "disable delegated_bypass" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_bypass])
    refute err
    assert @delegated_bypass_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_delegated_bypass])
    refute err
    refute @delegated_bypass_service.enabled?
  end

  context "can_enable" do
    test "returns false when secret scanning isn't enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @delegated_bypass_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_disabled
    end

    test "returns false when push protection isn't enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      SecurityProduct::TokenScanningPushProtection.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @delegated_bypass_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_push_protection_disabled
    end

    test "returns true if delegated bypass can be enabled" do
      can_enable, error = @delegated_bypass_service.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "can_disable" do
    test "returns true if delegated bypass can be disabled" do
      can_disable, error = @delegated_bypass_service.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  context "instrumentation" do
    test "emits event in audit log when repository delegated bypass is enabled" do
      event_name = "repository_secret_scanning_push_protection_bypass_list.enable"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_bypass])
        refute err
        assert @delegated_bypass_service.enabled?
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

    test "emits event in audit log when repository delegated bypass is disabled" do
      event_name = "repository_secret_scanning_push_protection_bypass_list.disable"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_delegated_bypass])
        refute err
        refute @delegated_bypass_service.enabled?
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
  end

  private

  def enable_token_scanning
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:advanced_security, :token_scanning, :token_scanning_push_protection])
    refute err
    assert @token_scanning_service.enabled?
    assert @push_protection_service.enabled?
  end
end
