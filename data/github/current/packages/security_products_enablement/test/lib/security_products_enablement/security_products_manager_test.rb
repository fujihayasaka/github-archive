# typed: true
# frozen_string_literal: true

require "test_helper"
class SecurityProductsManager < GitHub::TestCase
  include SecurityProductsEnablement::EnterpriseTestHelpers

  setup do
    # Ensure dependency graph preview is disabled for github-all-features build
    disable_feature_flag(:dependency_graph_preview)
  end

  test "returns true if dependency graph is enabled" do
    dg_enabled = SecurityProductsEnablement::SecurityProductsManager.new.dependency_graph_enabled?

    assert_equal true, dg_enabled
  end

  test "returns false if dependency graph is disabled" do
    GitHub.stubs(dependency_graph_enabled?: false)
    dg_disabled = SecurityProductsEnablement::SecurityProductsManager.new.dependency_graph_enabled?

    assert_equal false, dg_disabled
  end

  test "returns true if dependabot alerts are enabled" do
    alerts_enabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_alerts_enabled?

    assert_equal true, alerts_enabled
  end

  test "returns false if DG isn't enabled on GitHub Enterprise", enterprise_only: true do
    GitHub.stubs(dependency_graph_enabled?: false)
    alerts_disabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_alerts_enabled?

    assert_equal false, alerts_disabled
  end

  test "returns false if dependabot alerts aren't setup on GitHub Enterprise", enterprise_only: true do
    GitHub.stubs(ghe_content_analysis_enabled?: false)
    alerts_disabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_alerts_enabled?

    assert_equal false, alerts_disabled
  end

  test "returns true if dependabot security updates are enabled" do
    dependabot_enabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_security_updates_enabled?

    assert_equal true, dependabot_enabled
  end

  test "returns false if dependabot security updates are enabled but alerts isn't", enterprise_only: true do
    GitHub.stubs(ghe_content_analysis_enabled?: false)
    dependabot_disabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_security_updates_enabled?

    assert_equal false, dependabot_disabled
  end

  test "returns false if dependabot security updates are disabled" do
    GitHub.stubs(dependabot_enabled?: false)
    dependabot_disabled = SecurityProductsEnablement::SecurityProductsManager.new.dependabot_security_updates_enabled?

    assert_equal false, dependabot_disabled
  end

  test "returns true if code scanning is enabled" do
    code_scanning_enabled = SecurityProductsEnablement::SecurityProductsManager.new.code_scanning_default_setup_enabled?

    assert_equal true, code_scanning_enabled
  end

  test "returns false if code scanning is disabled" do
    GitHub.stubs(code_scanning_enabled?: false)
    code_scanning_disabled = SecurityProductsEnablement::SecurityProductsManager.new.code_scanning_default_setup_enabled?

    assert_equal false, code_scanning_disabled
  end

  test "requires code_scanning to have actions enabled" do
    GitHub.stubs(actions_enabled?: false)
    code_scanning_disabled = SecurityProductsEnablement::SecurityProductsManager.new.code_scanning_default_setup_enabled?

    assert_equal false, code_scanning_disabled
  end

  test "returns true if secret scanning is enabled" do
    secret_scanning_enabled = SecurityProductsEnablement::SecurityProductsManager.new.secret_scanning_enabled?

    assert_equal true, secret_scanning_enabled
  end

  test "returns false if secret scanning is disabled" do
    GitHub.stubs(configuration_secret_scanning_enabled?: false)
    secret_scanning_disabled = SecurityProductsEnablement::SecurityProductsManager.new.secret_scanning_enabled?

    assert_equal false, secret_scanning_disabled
  end

  context "on a non-GHAS enterprise instance", enterprise_only: true do
    test "secret scanning is disabled even if installed" do
      GitHub::Enterprise::LicenseMock.any_instance.stubs(advanced_security_enabled: false)
      GitHub::Enterprise::LicenseMock.any_instance.stubs(secret_protection_enabled: false)

      secret_scanning_enabled = SecurityProductsEnablement::SecurityProductsManager.new.secret_scanning_enabled?

      assert_equal false, secret_scanning_enabled
    end

    test "code scanning is disabled even if installed" do
      GitHub::Enterprise::LicenseMock.any_instance.stubs(advanced_security_enabled: false)
      GitHub::Enterprise::LicenseMock.any_instance.stubs(code_security_enabled: false)

      code_scanning_enabled = SecurityProductsEnablement::SecurityProductsManager.new.code_scanning_default_setup_enabled?

      assert_equal false, code_scanning_enabled
    end
  end

  test "returns true if private vulnerability reporting is enabled" do
    GitHub.stubs(private_vulnerability_reporting_enabled?: true)
    pvr_enabled = SecurityProductsEnablement::SecurityProductsManager.new.private_vulnerability_reporting_enabled?

    assert_equal true, pvr_enabled
  end

  test "returns false if private vulnerability reporting is disabled" do
    GitHub.stubs(private_vulnerability_reporting_enabled?: false)
    pvr_disabled = SecurityProductsEnablement::SecurityProductsManager.new.private_vulnerability_reporting_enabled?

    assert_equal false, pvr_disabled
  end

  test "returns a list of services that are NOT installed" do
    GitHub.stubs(
      private_vulnerability_reporting_enabled?: true,
      code_scanning_enabled?: false,
      dependabot_enabled?: false,
      dependency_graph_enabled?: false,
      dependency_graph_autosubmit_action_enabled?: false)
    disabled_services = SecurityProductsEnablement::SecurityProductsManager.new.disabled_services

    if GitHub.enterprise?
      assert_same_elements %i[code_scanning code_scanning_delegated_alert_dismissal dependabot_security_updates dependency_graph dependency_graph_autosubmit_action dependabot_alerts secret_scanning_validity_checks], disabled_services
    else
      assert_same_elements %i[code_scanning code_scanning_delegated_alert_dismissal dependabot_security_updates dependency_graph dependency_graph_autosubmit_action], disabled_services
    end
  end
end
