# typed: true
# frozen_string_literal: true

module ControllerMethods
  module SecurityAnalysisSettings
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    def owner; super; end
    def used_by_selection_view_packages; super; end

    sig do
      params(blocked_settings: BlockedSettings)
        .returns(Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data)
    end
    def create_toggled_settings_model(blocked_settings:)
      if blocked_settings.any?
        GitHub.dogstats.increment(
          "settings.security_features.enablement.blocking",
          tags: blocked_settings.blockers.map { |b| "blocked_by:#{b}" } + ["location:repo_settings"]
        )
      end

      # code scanning features
      begin
        @auto_codeql ||= CodeScanning::AutoCodeql.new(current_repository)

        code_scanning_enableable = @auto_codeql.can_enable?(actor: current_user, options: { skip_ghas_check?: true })
        code_scanning_default_setup_user_has_enabled = @auto_codeql.enabled? || @auto_codeql.enabling?
        code_scanning_default_setup_onboarding_status = @auto_codeql.auto_codeql_failed? ? "setup_failed" : @auto_codeql.onboarding_status
        code_scanning_default_setup_active_suite = @auto_codeql.active_query_suite
        code_scanning_default_setup_recommended_suite = CodeScanning::AutoCodeql.recommended_query_suite(current_repository)
      rescue CodeScanning::AutoCodeqlError => e
        Failbot.report e
        # Set defaults to avoid an inconsistent state in case of exceptions
        code_scanning_default_setup_user_has_enabled = false
        code_scanning_default_setup_onboarding_status = nil
        code_scanning_default_setup_active_suite = nil
        code_scanning_default_setup_recommended_suite = "default"
      end

      # Dependency graph features
      dependency_graph = SecurityProduct::DependencyGraph.new(current_repository)
      dependency_graph_autosubmit_action = SecurityProduct::DependencyGraphAutosubmitAction.new(current_repository)

      # Secret scanning features
      secret_scanning_ghas_token_scanning = SecretScanning::Features::Repo::TokenScanning.new(current_repository)
      secret_scanning_public_scanning = SecretScanning::Features::Repo::PublicScanning.new(current_repository)
      secret_scanning_push_protection = SecretScanning::Features::Repo::PushProtection.new(current_repository)
      secret_scanning_custom_patterns = SecretScanning::Features::Repo::CustomPatterns.new(current_repository)
      secret_scanning_validity_checks = SecretScanning::Features::Repo::ValidityChecks.new(current_repository)
      secret_scanning_lower_confidence_patterns = SecretScanning::Features::Repo::LowerConfidencePatterns.new(current_repository)
      secret_scanning_generic_secrets = SecretScanning::Features::Repo::GenericSecrets.new(current_repository)
      secret_scanning_delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(current_repository)
      secret_scanning_delegated_closures = SecretScanning::Features::Repo::DelegatedClosures.new(current_repository)

      validity_checks_enabled_by_org = secret_scanning_validity_checks.enabled_by == SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_ORGANIZATION
      validity_checks_enabled_by_business = secret_scanning_validity_checks.enabled_by == SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS
      validity_checks_enabled_by_owner = validity_checks_enabled_by_org || validity_checks_enabled_by_business

      lower_confidence_patterns_enabled_by_org = secret_scanning_lower_confidence_patterns.enabled_by_organization?
      lower_confidence_patterns_enabled_by_business = secret_scanning_lower_confidence_patterns.enabled_by_enterprise?
      lower_confidence_patterns_enabled_by_owner = lower_confidence_patterns_enabled_by_org || lower_confidence_patterns_enabled_by_business

      generic_secrets_enabled_by_org = secret_scanning_generic_secrets.enabled_by_organization?
      generic_secrets_enabled_by_business = secret_scanning_generic_secrets.enabled_by_enterprise?
      generic_secrets_enabled_by_owner = generic_secrets_enabled_by_org || generic_secrets_enabled_by_business

      dependabot_alerts_custom_rules_toggle_visible = current_repository.vulnerability_alerts_enabled? && GitHub.dependabot_rules_enabled?

      Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data.new(
        update_security_products_settings_path: update_security_products_settings_path(owner, current_repository),
        update_repository_ghas_settings_path: update_repository_ghas_settings_path(owner, current_repository),

        repository_security_configuration: RepositorySecurityConfiguration.find_by(repository: current_repository),

        show_unarchived_features: !current_repository.archived?,

        dependency_graph_enabled: dependency_graph.enabled?,
        dependency_graph_only_ghes_admin_toggle_allowed: GitHub.enterprise?,
        dependency_graph_subtitle_prompt:
          if GitHub.enterprise?
            safe_join([
                      "Contact your #{GitHub.flavor} administrators to ",
                      ActionController::Base.helpers.link_to(
                        "#{dependency_graph.enabled? ? "dis" : "en"}able Dependency Graph",
                        "#{GitHub.enterprise_admin_help_url(skip_version: true)}/configuration/enabling-alerts-for-vulnerable-dependencies-on-github-enterprise-server"
                      ),
                      "."]
                    )
          else
            if current_repository.public? && dependency_graph.enabled?
              "Dependency graph is always enabled for public repos."
            else
              ""
            end
          end,
        dependency_graph_always_enabled_for_public_repos: current_repository.public? && dependency_graph.enabled?,
        dependency_graph_toggle_visible: !GitHub.enterprise?,
        dependency_graph_disable_dependents_prompt:
          if current_repository.vulnerability_alerts_enabled?
            if current_repository.vulnerability_updates_enabled?
              "Disabling the dependency graph will also disable Dependabot alerts and Dependabot security updates."
            else
              "Disabling the dependency graph will also disable Dependabot alerts."
            end
          else
            nil
          end,
        dependency_graph_used_by_selection_view_model: if !GitHub.enterprise?
                                                         create_view_model(
                                                                 EditRepositories::AdminScreen::UsedBySelectionView,
                                                                 packages: used_by_selection_view_packages,
                                                                 repository: current_repository,
                                                               )
                                                       else
                                                         nil
                                                       end,
                                                       dependency_graph_blocked_by_policy: helpers.dependency_graph_blocked_by_policy?,

        dependency_graph_autosubmit_action_enabled: dependency_graph_autosubmit_action.enabled?,
        dependency_graph_autosubmit_action_use_labeled_runners: dependency_graph_autosubmit_action.labeled_runners_enabled?,
        dependency_graph_autosubmit_action_visible: dependency_graph_autosubmit_action.visible?,

        dependabot_alerts_toggle_visible: SecurityProduct::VulnerabilityAlerts.enabled_for_instance?,
        dependabot_alerts_admin_configuration_prompt: if GitHub.enterprise? && !SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
                                                        safe_join([
                                                          "Contact your #{GitHub.flavor} administrators to ",
                                                          ActionController::Base.helpers.link_to(
                                                            "allow Dependabot alerts to be enabled",
                                                            "#{GitHub.enterprise_admin_help_url(skip_version: true)}/configuration/enabling-alerts-for-vulnerable-dependencies-on-github-enterprise-server"
                                                          ),
                                                          "."
                                                        ])
                                                      else
                                                        nil
                                                      end,
        dependabot_alerts_enabled: current_repository.vulnerability_alerts_enabled?,
        dependabot_alerts_configure_notifications_href: if !GitHub.enterprise? || current_repository.vulnerability_alerts_enabled?
                                                          settings_notification_preferences_path(anchor: "vulnerability-alerts-heading")
                                                        else
                                                          nil
                                                        end,
        dependabot_alerts_disable_dependents_prompt: if GitHub.dependabot_enabled? && current_repository.vulnerability_updates_enabled?
                                                       "Disabling Dependabot alerts will also disable Dependabot security updates."
                                                     else
                                                       nil
                                                     end,
        dependabot_alerts_enable_prerequisites_prompt: if !dependency_graph.enabled?
                                                         "Dependabot alerts needs the dependency graph to be enabled, so we'll turn that on too."
                                                       else
                                                         nil
                                                       end,
                                                       dependabot_alerts_blocked_by_policy: helpers.dependabot_alerts_blocked_by_policy?,
        dependabot_alerts_custom_rules_toggle_visible: dependabot_alerts_custom_rules_toggle_visible,

        dependabot_security_updates_visible: true,
        dependabot_security_updates_admin_configuration_prompt: if GitHub.enterprise?
                                                                  safe_join([
                                                                          "Contact your #{GitHub.flavor} administrators to ",
                                                                          ActionController::Base.helpers.link_to(
                                                                            "#{current_repository.vulnerability_updates_enabled? ? "disable" : "enable"} Dependabot security updates",
                                                                            "#{GitHub.enterprise_admin_help_url(skip_version: true)}/configuration/enabling-alerts-for-vulnerable-dependencies-on-github-enterprise-server"
                                                                          ),
                                                                          "."])
                                                                else
                                                                  nil
                                                                end,
        dependabot_security_updates_toggle_visible: GitHub.dependabot_enabled?,
        dependabot_security_updates_enabled: GitHub.dependabot_enabled? && current_repository.vulnerability_updates_enabled?,
        dependabot_security_updates_enable_prerequisites_prompt:
         if !current_repository.vulnerability_alerts_enabled?
           (if !dependency_graph.enabled?
              "Dependabot security updates needs the dependency graph and Dependabot alerts to be enabled, so we'll turn them on too."
            else
              "Dependabot security updates needs Dependabot alerts to be enabled, so we'll turn that on too."
            end)
         else
           nil
         end,
        dependabot_security_updates_blocked_by_policy: helpers.dependabot_updates_blocked_by_policy?,

        dependabot_security_updates_grouping_visible: true,
        dependabot_security_updates_grouping_toggle_visible: GitHub.dependabot_enabled?,
        dependabot_security_updates_grouping_enabled: GitHub.dependabot_enabled? && current_repository.vulnerability_updates_grouping_enabled?,
        dependabot_security_updates_grouping_prerequisites_prompt: helpers.dependabot_security_updates_grouping_prerequisites_prompt,

        dependabot_on_actions_visible: !GitHub.single_or_multi_tenant_enterprise? && !current_repository.actions_disabled? && current_repository.dependabot_on_actions_feature_enabled?,
        dependabot_on_actions_toggle_visible: GitHub.dependabot_enabled? && !current_repository.actions_disabled? && current_repository.dependabot_on_actions_feature_enabled?,
        dependabot_on_actions_enabled: GitHub.dependabot_enabled? && current_repository.dependabot_on_actions_enabled?,
        dependabot_on_actions_prerequisites_prompt: nil,

        dependabot_self_hosted_visible: show_dependabot_self_hosted?,
        dependabot_self_hosted_toggle_visible: show_dependabot_self_hosted?,
        dependabot_self_hosted_enabled: GitHub.dependabot_enabled? && current_repository.dependabot_self_hosted_enabled?,
        dependabot_self_hosted_prerequisites_prompt: nil,

        dependabot_autofix_visible: show_dependabot_autofix?,
        dependabot_autofix_enabled: GitHub.dependabot_enabled? && current_repository.dependabot_autofix_enabled?,
        dependabot_autofix_prerequisites_prompt: nil,

        dependabot_version_updates_visible: GitHub.dependabot_enabled?,
        dependabot_version_updates_config_file_enabled: helpers.dependabot_version_updates_config_file_enabled?,
        dependabot_version_updates_config_file_repository_path: current_repository.dependabot_config_file_exists? ? current_repository.fetch_dependabot_config : nil,
        dependabot_version_updates_edit_config_href: if current_repository.dependabot_config_file_exists?
                                                       file_edit_path(current_repository.owner, current_repository, current_repository.default_branch, current_repository.fetch_dependabot_config)
                                                     else
                                                       nil
                                                     end,
        dependabot_version_updates_create_config_href: if !current_repository.dependabot_config_file_exists?
                                                         new_file_path(name: current_repository.default_branch, dependabot_template: 1, filename: ".github/dependabot.yml", repository: current_repository, user_id: owner)
                                                       else
                                                         nil
                                                       end,
        dependabot_version_updates_using_fork_policy: current_repository.fork?,
        dependabot_version_updates_fork_status_visible: current_repository.fork? &&
          (current_repository.dependabot_config_file_exists? || current_repository.dependabot_config_file_enabled?),

        ## Advanced Security
        **T.unsafe(self).advanced_security_settings_model_partial(blocked_settings:),

        # Proposed properties for code scanning settings model
        code_scanning_enabled: current_repository.code_scanning_enabled?,
        code_scanning_default_setup_visible: SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance? && !current_repository.code_scanning_enterprise_disabled? && helpers.advanced_security_configurable?,
        code_scanning_default_setup_eligible: !code_scanning_enableable.error?,
        code_scanning_default_setup_user_has_enabled: code_scanning_default_setup_user_has_enabled,
        code_scanning_default_setup_onboarding_status: code_scanning_default_setup_onboarding_status,
        code_scanning_default_setup_active_suite: code_scanning_default_setup_active_suite,
        code_scanning_default_setup_recommended_suite: code_scanning_default_setup_recommended_suite,
        code_scanning_default_setup_public_scanning_visible: current_repository.public? && GitHub.dotcom_request?,
        code_scanning_default_setup_prerequisite_error_message: CodeScanning::Status.prerequisites_error_to_message(CodeScanning::Status.validate_prerequisites(current_repository, current_user, options: { skip_ghas_check?: true, include_default_setup_prerequisites: true }), current_repository, current_user),
        code_scanning_default_setup_blocked_by_in_progress_setting: blocked_settings.code_scanning?,

        # Properties for dependabot alerts model
        dependabot_alerts_auto_dismissal_learn_more_link: helpers.dependabot_alerts_auto_dismissal_learn_more_link,

        secret_scanning_enabled_for_new_and_ghas_repos: current_repository.owner.organization? && SecretScanning::Features::Org::TokenScanning.new(current_repository.owner).secret_scanning_enabled_for_new_repos?,
        secret_scanning_blocked_by_policy: helpers.secret_scanning_blocked_by_policy?,
        secret_scanning_blocked_by_in_progress_setting: blocked_settings.secret_scanning?,
        secret_scanning_enabled: secret_scanning_ghas_token_scanning.enabled?,
        secret_scanning_public_scanning_enabled: secret_scanning_public_scanning.enabled?,
        secret_scanning_show_ghas_experience: helpers.show_secret_scanning_ghas_experience?(secret_scanning_ghas_token_scanning),
        secret_scanning_show_org_enablement_experience: secret_scanning_ghas_token_scanning.feature_available?,
        secret_scanning_show_custom_patterns: secret_scanning_custom_patterns.feature_available?,
        secret_scanning_show_requires_ghas: !current_repository.archived? && helpers.advanced_security_configurable? && !current_repository.advanced_security_enabled?,
        secret_scanning_enabled_for_instance: SecretScanning::Features::Owner::TokenScanning.new(current_repository.owner).feature_available?,

        secret_scanning_push_protection_enabled: secret_scanning_push_protection.enabled?,
        secret_scanning_push_protection_visible: secret_scanning_push_protection.feature_available?,
        secret_scanning_push_protection_blocked_by_policy: helpers.push_protection_blocked_by_policy?,
        secret_scanning_push_protection_blocked_by_in_progress_setting: blocked_settings.push_protection?,
        secret_scanning_push_protection_enabled_for_instance: SecretScanning::Features::Owner::PushProtection.new(current_repository.owner).feature_available?,

        secret_scanning_validity_checks_enabled: secret_scanning_validity_checks.enabled?,
        secret_scanning_validity_checks_visible: secret_scanning_validity_checks.feature_available?,
        secret_scanning_validity_checks_blocked_by_policy: helpers.validity_checks_blocked_by_policy?,
        secret_scanning_validity_checks_enabled_for_instance: secret_scanning_validity_checks.feature_available?,
        secret_scanning_validity_checks_enabled_by_owner: validity_checks_enabled_by_owner,
        secret_scanning_validity_checks_enabled_by_business: validity_checks_enabled_by_business,
        secret_scanning_validity_checks_enabled_by_org: validity_checks_enabled_by_org,
        secret_scanning_validity_checks_blocked_by_in_progress_setting: blocked_settings.secret_scanning?,
        secret_scanning_validity_checks_checkbox_disabled: blocked_settings.secret_scanning? || validity_checks_enabled_by_owner || helpers.validity_checks_blocked_by_policy?,

        secret_scanning_lower_confidence_patterns_enabled: secret_scanning_lower_confidence_patterns.enabled?,
        secret_scanning_lower_confidence_patterns_visible: secret_scanning_lower_confidence_patterns.feature_available?,
        secret_scanning_lower_confidence_patterns_blocked_by_policy: helpers.lower_confidence_patterns_blocked_by_policy?,
        secret_scanning_lower_confidence_patterns_enabled_by_owner: lower_confidence_patterns_enabled_by_owner,
        secret_scanning_lower_confidence_patterns_enabled_by_organization: lower_confidence_patterns_enabled_by_org,
        secret_scanning_lower_confidence_patterns_enabled_by_enterprise: lower_confidence_patterns_enabled_by_business,
        secret_scanning_lower_confidence_patterns_blocked_by_in_progress_setting: blocked_settings.secret_scanning?,
        secret_scanning_lower_confidence_patterns_checkbox_disabled: blocked_settings.secret_scanning? || lower_confidence_patterns_enabled_by_owner || helpers.lower_confidence_patterns_blocked_by_policy?,

        secret_scanning_generic_secrets_enabled: secret_scanning_generic_secrets.enabled?,
        secret_scanning_generic_secrets_visible: secret_scanning_generic_secrets.feature_available?,
        secret_scanning_generic_secrets_blocked_by_policy: helpers.generic_secrets_blocked_by_policy?,
        secret_scanning_generic_secrets_enabled_by_owner: generic_secrets_enabled_by_owner,
        secret_scanning_generic_secrets_enabled_by_organization: generic_secrets_enabled_by_org,
        secret_scanning_generic_secrets_enabled_by_enterprise: generic_secrets_enabled_by_business,
        secret_scanning_generic_secrets_blocked_by_in_progress_setting: blocked_settings.secret_scanning?,
        secret_scanning_generic_secrets_checkbox_disabled: blocked_settings.secret_scanning? || generic_secrets_enabled_by_owner || helpers.generic_secrets_blocked_by_policy?,

        secret_scanning_delegated_bypass_enabled: secret_scanning_delegated_bypass.enabled?,
        secret_scanning_delegated_bypass_visible: secret_scanning_delegated_bypass.feature_available?,
        secret_scanning_delegated_bypass_enabled_by_security_configuration: secret_scanning_delegated_bypass.enabled_by_security_configuration?,
        secret_scanning_delegated_bypass_disabled_by_security_configuration: secret_scanning_delegated_bypass.disabled_by_security_configuration?,

        secret_scanning_delegated_closures_enabled: secret_scanning_delegated_closures.enabled?,
        secret_scanning_delegated_closures_visible: secret_scanning_delegated_closures.feature_available?,
        secret_scanning_delegated_closures_blocked_by_in_progress_setting: blocked_settings.secret_scanning?,
      )
    end

    def allowed_repo_criteria
      if current_repository&.owner&.user?
        ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(T.cast(current_user, User))
        return true if ghas_for_users.feature_available?
      end
      render_404 unless current_repository.owner.organization?
    end

    def show_dependabot_self_hosted?
      return false if GitHub.single_tenant_enterprise?
      @dependabot_self_hosted_users ||= SecurityProduct::DependabotSelfHosted.new(current_repository)
      @dependabot_self_hosted_users.can_enable?(actor: current_user, options: {}).value
    end

    def show_dependabot_autofix?
      return false if GitHub.single_tenant_enterprise?

      @dependabot_autofix_users ||= SecurityProduct::DependabotAutofix.new(current_repository)
      @dependabot_autofix_users.can_enable?(actor: current_user, options: {}).value
    end
  end
end
