# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class BusinessWarningHelperTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers

    setup do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @biz = create(:global_business)
      @org = create(:organization, business: @biz)

      security_configs_docs_link = "#{GitHub.help_url}/code-security/securing-your-organization/introduction-to-securing-your-organization-at-scale/about-enabling-security-features-at-scale"
      @expected_text = "This may override <a href='#{security_configs_docs_link}'>code security configurations</a> which have been applied at the organization level."
    end

    context "#banner_text" do
      test "returns nil if owner is not a business" do
        helper = SecurityProductsEnablement::BusinessWarningHelper.new(create(:organization))
        assert_nil helper.banner_text(setting: :enable_ghas, value: true)
      end

      test "returns nil if the business does not have any orgs" do
        helper = SecurityProductsEnablement::BusinessWarningHelper.new(create(:global_business))
        assert_nil helper.banner_text(setting: :enable_ghas, value: true)
      end

      test "returns text if the business has more than ORGS_LIMIT orgs" do
        SecurityProductsEnablement::BusinessWarningHelper.stub_const(:ORGS_LIMIT, 1) do
          create(:organization, business: @biz)
          create(:security_configuration, :not_set, target: @org, enable_ghas: true)

          result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :enable_ghas, value: true)

          assert_equal @expected_text, result
        end
      end

      # Dependabot Alerts
      test "returns text if enterprise clicks enable all for dependabot_alerts and an org has dependabot_alerts set to disabled" do
        create(:security_configuration, target: @org, dependabot_alerts: "disabled", dependabot_security_updates: "disabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :dependabot_alerts, value: "enabled")
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks enable all for dependabot_alerts and no org has dependabot_alerts set to disabled" do
        create(:security_configuration, target: @org, dependency_graph: "enabled", dependabot_alerts: "enabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :dependabot_alerts, value: "enabled")
      end

      test "returns text if enterprise clicks disable all for dependabot_alerts and an org has dependabot_alerts set to enabled" do
        create(:security_configuration, target: @org, dependency_graph: "enabled", dependabot_alerts: "enabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :dependabot_alerts, value: "disabled")
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks disable all for dependabot_alerts and no org has dependabot_alerts set to enabled" do
        create(:security_configuration, target: @org, dependabot_alerts: "disabled", dependabot_security_updates: "disabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :dependabot_alerts, value: "disabled")
      end

      test "returns nil if enterprise clicks disable all for dependabot alerts and an org has dependabot_alerts set to not_set" do
        create(:security_configuration, :not_set, target: @org)
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :dependabot_alerts, value: "disabled")
      end

      # GHAS
      test "returns text if enterprise clicks enable all for ghas and an org has a config w/ enable_ghas set to false" do
        create(:security_configuration, target: @org, enable_ghas: false, code_scanning: "disabled", secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :enable_ghas, value: true)
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks enable all for ghas and no org has enable_ghas set to false" do
        create(:security_configuration, target: @org, enable_ghas: true)
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :enable_ghas, value: true)
      end

      test "returns text if enterprise clicks disable all for ghas and an org has a config w/ enable_ghas set to true" do
        create(:security_configuration, target: @org, enable_ghas: true)
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :enable_ghas, value: false)
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks disable all for ghas and no org has enable_ghas set to true" do
        create(:security_configuration, target: @org, enable_ghas: false, code_scanning: "disabled", secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :enable_ghas, value: false)
      end

      # Secret Scanning
      test "returns text if enterprise clicks enable all for secret_scanning and an org has a config w/ secret_scanning set to disabled" do
        create(:security_configuration, target: @org, secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning, value: "enabled")
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks enable all for secret_scanning and no org has a config w/ secret_scanning set to disabled" do
        create(:security_configuration, target: @org, secret_scanning: "enabled", secret_scanning_push_protection: "enabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning, value: "enabled")
      end

      test "returns text if enterprise clicks disable all for secret_scanning and an org has a config w/ secret_scanning set to enabled" do
        create(:security_configuration, target: @org, secret_scanning: "enabled", secret_scanning_push_protection: "enabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning, value: "disabled")
        assert_equal @expected_text, result
      end

      test "returns nil if enterprise clicks disable all for secret_scanning and no org has a config w/ secret_scanning set to enabled" do
        create(:security_configuration, target: @org, secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning, value: "disabled")
      end

      # Push protection
      test "return text if enterprise clicks enable all for push_protection and an org has a config w/ push_protection set to disabled" do
        create(:security_configuration, target: @org, secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning_push_protection, value: "enabled")
        assert_equal @expected_text, result
      end

      test "return nil if enterprise clicks enable all for push_protection and no org has a config w/ push_protection set to disabled" do
        create(:security_configuration, target: @org, secret_scanning_push_protection: "enabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning_push_protection, value: "enabled")
      end

      test "return text if enterprise clicks disable all for push_protection and an org has a config w/ push_protection set to enabled" do
        create(:security_configuration, target: @org, secret_scanning_push_protection: "enabled")
        result = SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning_push_protection, value: "disabled")
        assert_equal @expected_text, result
      end

      test "return nil if enterprise clicks disable all for push_protection and no org has a config w/ push_protection set to enabled" do
        create(:security_configuration, target: @org, secret_scanning: "disabled", secret_scanning_push_protection: "disabled")
        assert_nil SecurityProductsEnablement::BusinessWarningHelper.new(@biz).banner_text(setting: :secret_scanning_push_protection, value: "disabled")
      end
    end
  end
end
