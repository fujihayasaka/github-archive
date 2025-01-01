# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisDependabotAlertsComponent < ApplicationComponent
    extend T::Sig
    include SecurityAnalysisSettingsHelper

    sig { returns(T.untyped) }
    attr_reader :owner

    sig { returns(Integer) }
    attr_reader :repo_count

    sig { returns(Integer) }
    attr_reader :private_repo_count

    sig { params(owner: T.untyped, repo_count: Integer, private_repo_count: Integer).void }
    def initialize(owner:, repo_count:, private_repo_count:)
      @owner = owner
      @repo_count = repo_count
      @private_repo_count = private_repo_count
    end

    private

    sig { returns(String) }
    def security_alerts_test_selector_text
      @owner.is_a?(Business) ? "security-alerts-business-settings" : "security-alerts-org-settings"
    end

    sig { returns(String) }
    def dependabot_alerts_enablement_dialog_text
      "You're about to enable Dependabot alerts on all #{user_or_org_text(@owner, false)}.
      Alerts require the dependency graph, so we'll also turn that on for all repositories.
      No notifications will be sent while Dependabot alerts are being enabled."
    end

    sig { returns(T::Boolean) }
    memoize def dependabot_alerts_enabled_for_instance?
      SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
    end

    sig { returns(String) }
    def github_connect_enterprise_url
      # The path is missing from the rbi file. Other paths in config/routes/enterprises.rb are also mssing
      # even after running `bin/tapioca dsl`. The check `if GitHub.single_business_environment?` is preventing
      # the helper from being loaded.
      T.unsafe(self).admin_settings_dotcom_connection_enterprise_path(@owner.slug)
    end

    def dependabot_rules_enabled?
      @owner.organization? && GitHub.dependabot_rules_enabled?
    end

    sig { params(value: String).returns(T.nilable(String)) }
    def security_config_warning_banner_text(value:)
      warning_banner_helper.banner_text(setting: :dependabot_alerts, value:)
    end

    sig { returns(SecurityProductsEnablement::BusinessWarningHelper) }
    memoize def warning_banner_helper
      SecurityProductsEnablement::BusinessWarningHelper.new(@owner)
    end
  end
end
