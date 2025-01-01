# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisGhasComponent < ApplicationComponent
    include SecurityAnalysisSettingsHelper

    attr_reader :owner, :blocked_settings

    def initialize(owner:, repo_count:, private_repo_count:, blocked_settings: nil, security_configs_warning_banner_helper: nil)
      @owner = owner
      @repo_count = repo_count
      @private_repo_count = private_repo_count
      @blocked_settings = blocked_settings || BlockedSettings.new(owner)
      @security_configs_warning_banner_helper = security_configs_warning_banner_helper || SecurityProductsEnablement::BusinessWarningHelper.new(owner)
    end

    def render?
      @owner.advanced_security_configurable?
    end

    private

    memoize def show_enterprise_user_settings?
      return false unless @owner.is_a?(Business)

      AdvancedSecurity::Features::Business::AdvancedSecurity.new(@owner).feature_available_for_user_repositories?
    end

    memoize def advanced_security_blocked_by_in_progress_setting?
      blocked_settings.advanced_security?
    end

    # Is the enable GHAS button blocked by the business policy?
    memoize def advanced_security_blocked_by_policy?
      # This component is only used when the entity is bundled, so all of GHAS is controlled at once.
      !@owner.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL)
    end

    memoize def advanced_security_blocked_by_connect?
      SecurityProduct::AdvancedSecurity.blocked_by_connect?
    end

    def button_disabled_no_repos(include_public_repos: false)
      (include_public_repos || GitHub.enterprise?) ? @repo_count.zero? : @private_repo_count.zero?
    end

    def button_disabled_no_repos_title(title, include_public_repos: false)
      button_disabled_no_repos(include_public_repos: include_public_repos) ? "No applicable repositories" : title
    end

    def security_analysis_update_path(owner)
      if owner.organization?
        settings_org_security_analysis_update_path(owner, owner: owner)
      elsif owner.is_a?(Business)
        raise ArgumentError, "Business owners are no longer supported!"
      else
        settings_security_analysis_path
      end
    end

    memoize def tooltip_text
      blocked_settings.preface
    end

    def security_config_warning_banner_text(value:)
      @security_configs_warning_banner_helper.banner_text(setting: :enable_ghas, value:)
    end
  end
end
