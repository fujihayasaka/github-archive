# typed: true
# frozen_string_literal: true

module Repositories
  class SecurityOverviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include Repos::AdvisoriesHelper
    include SecretScanning::Features::FeatureFlagHelper
    attr_reader :repository, :current_user

    def indicators_for_display(state)
      case state
      when :enabled
        ["Enabled", :success]
      when :disabled
        ["Disabled", :muted]
      when :needs_setup
        ["Needs setup", :muted]
      end
    end

    def enablement_state(condition)
      condition ? :enabled : :disabled
    end

    # security policy

    def security_policy_exists?
      repository.security_policy.exists?
    end

    def security_policy_path
      urls.repository_security_policy_path(repository.owner, repository)
    end

    def security_policy_editable?
      repository.pushable_by?(current_user)
    end

    # Dependabot alerts

    # is the Dependabot alerts tab available
    def vulnerability_alerts_show?
      repository.can_view_vulnerability_alerts?(current_user)
    end

    # is the Dependabot alerts feature turned on for this repo
    def vulnerability_alerts_configured?
      repository.vulnerability_alerts_enabled?
    end

    # can the current user control the Dependabot alerts feature
    def vulnerability_alerts_configurable?
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
    end

    def vulnerability_alerts_view_path
      urls.repository_alerts_path(repository.owner, repository)
    end

    # code scanning

    def code_scanning_show?
      repository.show_code_scanning?(current_user)
    end

    def code_scanning_ghas_required_but_not_purchased?
      return false if repository.code_scanning_enabled?
      if repository.advanced_security_products_bundled?
        repository.owner.organization? && !repository.owner.advanced_security_purchased? && repository.private?
      else
        repository.owner.organization? && !repository.owner.code_security_purchased? && repository.private?
      end
    end

    def code_scanning_configured?
      repository.turboscan_considers_code_scanning_enabled?
    end

    # Is GHAS purchased for this repo, currently not enabled, but could be enabled.
    def ghas_required_and_purchased_but_not_enabled?
      return false unless repository.advanced_or_code_security_required_for_code_scanning?
      if repository.advanced_security_products_bundled?
        repository.owner.advanced_security_purchased? &&
        !repository.advanced_security_enabled? &&
        # want to return false for user-owned repos as there is no UI for them to enable GHAS
        repository.advanced_security_configurable?
      else
        repository.owner.code_security_purchased? &&
        !CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository:) &&
        # want to return false for user-owned repos as there is no UI for them to enable Code Security
        CodeSecurity::Features::AdvancedSecurityHelper.code_security_configurable?(repository:)
      end
    end

    def private_user_owned_cloud_repo?
      !GitHub.enterprise? && repository.private? && !repository.owner.organization?
    end

    def user_owned_ghes_repo?
      GitHub.enterprise? &&
        !repository.owner.organization?
    end

    def code_scanning_configurable?
      repository.code_scanning_readable_by?(current_user)
    end

    def can_manage_security_products?
      if repository.owner&.organization?
        SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
      else
        repository.adminable_by?(current_user)
      end
    end

    def code_scanning_configure_path
      if can_manage_security_products?
        urls.repository_security_and_analysis_path(repository.owner, repository, anchor: "code_scanning_settings")
      else
        urls.repository_code_scanning_results_path(repository.owner, repository)
      end
    end

    def code_scanning_view_path
      urls.repository_code_scanning_results_path(repository.owner, repository)
    end

    def about_code_scanning_docs_url
      DocsUrlConfig.url_for("code-security/about-code-scanning")
    end

    # token scanning
    def token_scanning
      @token_scanning ||= SecretScanning::Features::Repo::TokenScanning.new(repository)
    end

    def token_scanning_show?
      # Hide the "enable in settings" link if GHAS usage is blocked by the policy
      return false if repository.advanced_security_configurable? &&
        !repository.advanced_security_enabled? &&
        !repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY)

      token_scanning.view_alerts_allowed?(current_user)
    end

    def token_scanning_configured?
      token_scanning.enabled?
    end

    def token_scanning_configurable?
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
    end

    def token_scanning_view_path
      urls.repository_token_scanning_results_path(repository.owner, repository)
    end

    # security advisories

    # is the security advisories tab available
    def security_advisories_show?
      repository.advisories_enabled?
    end

    def security_advisories_view_path(state: nil)
      urls.repository_advisories_path(repository.owner, repository, state:)
    end

    # can the current user create security advisories, or only view them
    def security_advisories_creatable?
      repository.advisory_management_authorized_for?(current_user)
    end

    # Private Vulnerability Reporting

    def private_vulnerability_reporting_configurable?
      return @private_vulnerability_reporting_configurable if defined?(@private_vulnerability_reporting_configurable)

      @private_vulnerability_reporting_configurable = SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products? &&
        repository.public &&
        !repository.archived? &&
        repository.advisories_enabled?
    end

    # can the current user see the PVR box
    def private_vulnerability_reporting_show?
      private_vulnerability_reporting_configurable? || pvd_authorized? || pvd_without_login?
    end

    def pvd_authorized?
      use_pvd_workflow?(repository: repository)
    end

    def pvd_without_login?
      return false unless repository.private_vulnerability_reporting_enabled?

      current_user.nil?
    end

    # Security Overview
    def show_security_overview_link?
      return false unless repository.owner.is_a?(Organization)
      return false unless repository.owner.direct_or_team_member?(current_user)

      ::SecurityCenter::SecurityFeatures.security_center_available?(repository.owner)
    end
  end
end
