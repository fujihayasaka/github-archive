# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisSecretScanningComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    attr_reader :blocked_settings, :owner

    def initialize(owner:, repo_count:, public_repo_count:, query: "", cursor: nil, blocked_settings: nil, security_configs_warning_banner_helper: nil)
      @owner = owner
      @repo_count = repo_count
      @public_repo_count = public_repo_count
      @query = query
      @cursor = cursor
      @blocked_settings = blocked_settings || BlockedSettings.new(owner)
      @security_configs_warning_banner_helper = security_configs_warning_banner_helper || SecurityProductsEnablement::BusinessWarningHelper.new(owner)
    end

    private

    # Display the secret scanning toggle if the secret scanning feature is available
    def render?
      token_scanning.feature_available?
    end

    memoize def token_scanning
      SecretScanning::Features::Owner::TokenScanning.new(@owner)
    end

    memoize def push_protection
      SecretScanning::Features::Owner::PushProtection.new(@owner)
    end

    memoize def validity_checks
      SecretScanning::Features::Owner::ValidityChecks.new(@owner)
    end

    sig { returns(SecretScanning::Features::Owner::LowerConfidencePatterns) }
    memoize def lower_confidence_patterns
      SecretScanning::Features::Owner::LowerConfidencePatterns.new(@owner)
    end

    sig { returns(SecretScanning::Features::Owner::GenericSecrets) }
    memoize def generic_secrets
      SecretScanning::Features::Owner::GenericSecrets.new(@owner)
    end

    sig { returns(SecretScanning::Features::Org::DelegatedClosures) }
    memoize def delegated_closures
      SecretScanning::Features::Org::DelegatedClosures.new(@owner)
    end

    memoize def advanced_security_purchased?
      @owner.advanced_security_purchased?
    end

    # Is the enable GHAS button blocked by the business policy?
    memoize def advanced_security_blocked_by_policy?
      !@owner.policy_allows_advanced_security_enablement?
    end

    memoize def push_protection_buttons_disabled?
      blocked_settings.push_protection?
    end

    memoize def secret_scanning_buttons_disabled?
      blocked_settings.secret_scanning?
    end

    memoize def validity_checks_toggle_disabled?
      blocked_settings.secret_scanning?
    end

    memoize def validity_checks_buttons_disabled?
      blocked_settings.validity_checks?
    end

    memoize def lower_confidence_patterns_toggle_disabled?
      blocked_settings.secret_scanning?
    end

    memoize def lower_confidence_patterns_buttons_disabled?
      blocked_settings.lower_confidence_patterns?
    end

    sig { returns(T::Boolean) }
    memoize def generic_secrets_toggle_disabled?
      blocked_settings.secret_scanning?
    end

    sig { returns(T::Boolean) }
    memoize def generic_secrets_buttons_disabled?
      blocked_settings.generic_secrets?
    end

    memoize def tooltip_text
      blocked_settings.preface
    end

    memoize def button_disabled_no_repos
      if GitHub.enterprise? || advanced_security_purchased?
        @repo_count.zero?
      else
        @public_repo_count.zero?
      end
    end

    def button_disabled_no_repos_title(title)
      button_disabled_no_repos ? "No applicable repositories" : title
    end

    def security_analysis_update_path(owner)
      if owner.organization?
        settings_org_security_analysis_update_path(owner, owner: owner)
      elsif owner.is_a?(Business)
        settings_security_analysis_update_enterprise_path(owner, owner: owner)
      else
        settings_security_analysis_path
      end
    end

    # Only organizations and businesses can enable secret scanning for new repos
    # For free users, all public repos are automatically enabled
    # The option should still exist for EMU accounts
    def can_owner_enable_for_new_repos?
      token_scanning.can_enable_for_new_repos?
    end

    def checked_condition_enabled_for_new_repos(owner)
      if owner.organization?
        SecretScanning::Features::Org::TokenScanning.new(@owner).secret_scanning_enabled_for_new_repos?
      elsif owner.is_a?(Business)
        SecretScanning::Features::Business::TokenScanning.new(@owner).secret_scanning_enabled_for_new_repos?
      elsif owner.user?
        SecretScanning::Features::User::TokenScanning.new(@owner).secret_scanning_enabled_for_new_repos?
      end
    end

    def secret_scanning_new_repos_label_calculated(owner)
      "Automatically enable for new #{secret_scanning_scope_label(owner)}"
    end

    def secret_scanning_enable_dialog_main_text_calculated(owner)
      "This will turn on secret scanning for all #{secret_scanning_scope_label(owner)}"
    end

    def secret_scanning_scope_label(owner)
      message = ""
      if owner.advanced_security_purchased?
        message += "public repositories and " unless GitHub.single_or_multi_tenant_enterprise?
        message += "repositories with GitHub Advanced Security enabled"
      else
        message += "public repositories"
      end
      message
    end

    def secret_scanning_push_protection_feature_available?
      push_protection.feature_available?
    end

    def secret_scanning_push_protection_enabled_for_new_repos?
      push_protection.enabled_for_new_repos?
    end

    def push_protection_custom_message_enabled?
      push_protection.custom_message_enabled?
    end

    def push_protection_custom_message_doc_link
      "#{GitHub.help_url}/code-security/secret-scanning/protecting-pushes-with-secret-scanning#using-secret-scanning-as-a-push-protection-from-the-command-line"
    end

    def push_protection_custom_message
      @owner.get_push_protection_custom_message
    end

    memoize def render_async_counts?
      return false unless @owner.organization?
      SecurityCenter::SecurityFeatures.security_center_available?(@owner)
    end

    sig { returns(T::Boolean) }
    def validity_checks_feature_available?
      return false if @owner.user?
      #do not show validity checks for org in security config experience
      return false if @owner.organization? && validity_checks.show_security_config_ux?
      T.must(validity_checks).feature_available?
    end

    sig { returns(T::Boolean) }
    def validity_checks_show_enable_all?
      validity_checks.show_security_config_ux?
    end

    def secret_scanning_validity_checks_enabled_for_new_repos?
      validity_checks.enabled_for_new_repos?
    end

    sig { returns(T::Boolean) }
    def validity_checks_enabled?
      return false if validity_checks.nil?
      T.must(validity_checks).enabled?
    end

    sig { returns(T::Boolean) }
    memoize def validity_checks_enabled_by_owning_business?
      if @owner.is_a?(Business)
        return false
      end
      business = @owner.business
      return false unless business.present?
      business_validity_checks = SecretScanning::Features::Business::ValidityChecks.new(business)
      business_validity_checks.enabled?
    end

    sig { returns(T::Boolean) }
    def show_partner_notification_subtext?
      @owner.user? && token_scanning.feature_available?
    end

    sig { returns(T::Boolean) }
    def lower_confidence_patterns_feature_available?
      return false unless @owner.present?
      return false if @owner.user?
      return false if @owner.organization? && T.must(lower_confidence_patterns).show_security_config_ux?
      T.must(lower_confidence_patterns).feature_available?
    end

    sig { returns(T::Boolean) }
    def lower_confidence_patterns_show_enable_all?
      T.must(lower_confidence_patterns).show_security_config_ux?
    end

    def secret_scanning_lower_confidence_patterns_enabled_for_new_repos?
      false unless @owner.business?
      T.must(lower_confidence_patterns).enabled_for_new_repos?
    end

    sig { returns(T::Boolean) }
    def lower_confidence_patterns_enabled?
      T.must(lower_confidence_patterns).enabled?
    end

    sig { returns(T::Boolean) }
    def lower_confidence_patterns_enabled_by_owning_business?
      return false unless @owner.present?
      T.must(lower_confidence_patterns).enabled_by_owning_business?
    end

    sig { returns(T::Boolean) }
    memoize def lower_confidence_patterns_enablement_blocked?
      blocked_settings.secret_scanning? || lower_confidence_patterns_enabled_by_owning_business?
    end

    sig { returns(T::Boolean) }
    def generic_secrets_feature_available?
      return false unless @owner.present?
      return false if @owner.user?
      return false if @owner.organization? && generic_secrets.show_security_config_ux?
      generic_secrets.feature_available?
    end

    sig { returns(T::Boolean) }
    def generic_secrets_show_enable_all?
      return false unless @owner.present?
      generic_secrets.show_security_config_ux?
    end

    sig { returns(T::Boolean) }
    def secret_scanning_generic_secrets_enabled_for_new_repos?
      return false unless @owner.present?
      return false unless @owner.business?
      generic_secrets.enabled_for_new_repos?
    end

    sig { returns(T::Boolean) }
    def generic_secrets_enabled?
      return false unless @owner.present?
      generic_secrets.enabled?
    end

    sig { returns(T::Boolean) }
    def generic_secrets_enabled_by_owning_business?
      return false unless @owner.present?
      generic_secrets.enabled_by_owning_business?
    end

    sig { returns(T::Boolean) }
    memoize def generic_secrets_enablement_blocked?
      return true if blocked_settings.secret_scanning? || generic_secrets_enabled_by_owning_business?
      if @owner.organization?
        business = @owner.business
        if business.present?
          return !business.repo_admins_can_modify_generic_secrets_settings?
        end
      end
      false
    end

    def security_config_warning_banner_text(setting:, value:)
      @security_configs_warning_banner_helper.banner_text(setting:, value:)
    end

    sig { returns(T::Boolean) }
    def delegated_closures_feature_available?
      return false unless @owner.present?
      return false unless @owner.organization?
      delegated_closures.feature_available?
    end

    sig { returns(T::Boolean) }
    def delegated_closures_enabled?
      delegated_closures.enabled?
    end
  end
end
