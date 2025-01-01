# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class SecurityAnalysisEnablementFormComponent < ApplicationComponent
      Data = Struct.new(
        :update_security_products_settings_path,
        :update_repository_ghas_settings_path,

        :repository_security_configuration, # Used to show banner with name of security config applied

        :show_unarchived_features, # Show features that are available for non-archived repos - everything besides Secret Scanning

        # Dependency Graph section is always visible for non-archived repos
        :dependency_graph_only_ghes_admin_toggle_allowed, # True for GHES, false otherwise - shows link to docs
        :dependency_graph_always_enabled_for_public_repos, # True for public repos on dotcom
        :dependency_graph_toggle_visible, # Show the toggle button. On GHES, this is false because DG is set up by admins.
        :dependency_graph_enabled,
        :dependency_graph_toggle_allowed,
        :dependency_graph_subtitle_prompt, # Displays current status of DG, e.g. if it needs to be enabled by admin or is already force-enabled for public repos
        :dependency_graph_disable_dependents_prompt, # Optional prompt, enumerating which dependent features will also be disabled
        :dependency_graph_used_by_selection_view_model, # Additional data showing how many projects depend on this repository
        :dependency_graph_blocked_by_policy,
        :dependency_graph_autosubmit_action_enabled, # Defaults to false, true tells Dependency Graph Platform to listen to pushes and trigger dynamic actions for supported languages.
        :dependency_graph_autosubmit_action_use_labeled_runners, # Defaults to false, true tells Dependency Graph Platform to set `runs_on` to self-hosted using a feature label
        :dependency_graph_autosubmit_action_visible, # Boolean indicating the autosubmission prerequisites are met

        # Dependabot Alerts toggle is always allowed, if visible (which based on prerequisites)
        :dependabot_alerts_auto_dismissal_learn_more_link,
        :dependabot_alerts_toggle_visible,
        :dependabot_alerts_enabled,
        :dependabot_alerts_blocked_by_policy,
        :dependabot_alerts_configure_notifications_href, # Link to notifications setup screen
        :dependabot_alerts_admin_configuration_prompt, # Optional link to Connect setup docs
        :dependabot_alerts_disable_dependents_prompt, # Optional, can be used to show dialog prompting that this will disable dependent features
        :dependabot_alerts_enable_prerequisites_prompt, # Optional, can be used to show dialog prompting this will also enable prerequisites
        :dependabot_alerts_custom_rules_toggle_visible, # Optional, can be used to show component for toggling custom rules feature

        :dependabot_security_updates_visible,
        :dependabot_security_updates_toggle_visible,
        :dependabot_security_updates_enabled,
        :dependabot_security_updates_enable_prerequisites_prompt, # Optional, can be used to show dialog prompting that this will also enable prerequisites
        :dependabot_security_updates_blocked_by_policy,
        :dependabot_security_updates_admin_configuration_prompt, # Optional link to Connect setup docs

        :dependabot_security_updates_grouping_visible,
        :dependabot_security_updates_grouping_toggle_visible,
        :dependabot_security_updates_grouping_enabled,
        :dependabot_security_updates_grouping_prerequisites_prompt, # Optional, can be used to show dialog prompting that this will also enable prerequisites

        :dependabot_on_actions_visible,
        :dependabot_on_actions_toggle_visible,
        :dependabot_on_actions_enabled,
        :dependabot_on_actions_prerequisites_prompt, # Optional, can be used to show dialog prompting that this will also enable prerequisites

        :dependabot_self_hosted_visible,
        :dependabot_self_hosted_toggle_visible,
        :dependabot_self_hosted_enabled,
        :dependabot_self_hosted_prerequisites_prompt, # Optional, can be used to show dialog prompting that this will also enable prerequisites

        :dependabot_autofix_visible,
        :dependabot_autofix_enabled,
        :dependabot_autofix_prerequisites_prompt, # Optional, can be used to show dialog prompting that this will also enable prerequisites

        # Version updates can be configured via file, not enabled directly
        :dependabot_version_updates_visible,
        :dependabot_version_updates_config_file_enabled, # Defaults to false, determines whether any checked-in file is used or ignored
        :dependabot_version_updates_config_file_repository_path, # Optional path to the config file within the repository content
        :dependabot_version_updates_edit_config_href, # Optional URL to edit an existing config file
        :dependabot_version_updates_create_config_href, # Option URL to create a new config file
        :dependabot_version_updates_using_fork_policy, # Defaults to false, forks use a different policy which ignores any config files by default
        :dependabot_version_updates_fork_status_visible, # Defaults to false, shows the activation state of any checked-in file for forks only

        :advanced_security_visible,
        :advanced_security_enabled,
        :advanced_security_license_prompt, # Prompt showing details of license usage
        :advanced_security_toggle_allowed,
        :advanced_security_blocked_by_policy, # This might be indirectly blocked due to dependents being blocked
        :advanced_security_blocked_by_in_progress_setting, # Whether or not a setting which temporarily blocks changing GHAS is being applied to all repos of this org/user.
        :advanced_security_show_blocked_by_policy_message, # Displays additional message when advanced security is directly blocked
        :advanced_security_will_exceed_seat_allowance,
        :advanced_security_blocked_by_seat_count_message, # Message to show when previous flag is true
        :advanced_security_billing_learn_more_href, # Link to billing page
        :advanced_security_billed_repositories_description, # Dynamic sentence explaining how we bill for GHAS
        :advanced_security_blocked_by_backfill,
        :advanced_security_enablement_status,
        :advanced_security_blocked_by_turboghas_error,
        :advanced_security_blocked_by_connect_error,

        # Code scanning toggle is always allowed, but depends on prerequisites
        :code_scanning_enabled,
        :code_scanning_default_setup_visible,
        :code_scanning_default_setup_eligible,
        :code_scanning_default_setup_user_has_enabled,
        :code_scanning_default_setup_onboarding_status,
        :code_scanning_default_setup_active_suite,
        :code_scanning_default_setup_recommended_suite,
        :code_scanning_default_setup_public_scanning_visible,
        :code_scanning_default_setup_prerequisite_error_message,
        :code_scanning_default_setup_blocked_by_in_progress_setting,

        :secret_scanning_enabled,
        :secret_scanning_public_scanning_enabled,
        :secret_scanning_show_free_experience,
        :secret_scanning_show_ghas_experience,
        :secret_scanning_show_org_enablement_experience,
        :secret_scanning_show_custom_patterns,
        :secret_scanning_show_requires_ghas,
        :secret_scanning_enabled_for_new_and_ghas_repos,
        :secret_scanning_blocked_by_policy,
        :secret_scanning_blocked_by_in_progress_setting, # Whether or not a setting which temporarily blocks changing secret scanning is being applied to all repos of this org/user.
        :secret_scanning_enabled_for_instance,

        :secret_scanning_push_protection_enabled,
        :secret_scanning_push_protection_visible,
        :secret_scanning_push_protection_blocked_by_policy,
        :secret_scanning_push_protection_blocked_by_in_progress_setting, # Whether or not a setting which temporarily blocks changing secret scanning push protection is being applied to all repos of this org/user.
        :secret_scanning_push_protection_enabled_for_instance,

        :secret_scanning_validity_checks_enabled,
        :secret_scanning_validity_checks_visible,
        :secret_scanning_validity_checks_blocked_by_policy,
        :secret_scanning_validity_checks_enabled_for_instance,
        :secret_scanning_validity_checks_enabled_by_owner,
        :secret_scanning_validity_checks_enabled_by_business,
        :secret_scanning_validity_checks_enabled_by_org,
        :secret_scanning_validity_checks_blocked_by_in_progress_setting,
        :secret_scanning_validity_checks_checkbox_disabled,

        :secret_scanning_lower_confidence_patterns_enabled,
        :secret_scanning_lower_confidence_patterns_visible,
        :secret_scanning_lower_confidence_patterns_blocked_by_policy,
        :secret_scanning_lower_confidence_patterns_enabled_by_owner,
        :secret_scanning_lower_confidence_patterns_enabled_by_organization,
        :secret_scanning_lower_confidence_patterns_enabled_by_enterprise,
        :secret_scanning_lower_confidence_patterns_blocked_by_in_progress_setting,
        :secret_scanning_lower_confidence_patterns_checkbox_disabled,

        :secret_scanning_generic_secrets_enabled,
        :secret_scanning_generic_secrets_visible,
        :secret_scanning_generic_secrets_blocked_by_policy,
        :secret_scanning_generic_secrets_enabled_by_owner,
        :secret_scanning_generic_secrets_enabled_by_organization,
        :secret_scanning_generic_secrets_enabled_by_enterprise,
        :secret_scanning_generic_secrets_blocked_by_in_progress_setting,
        :secret_scanning_generic_secrets_checkbox_disabled,

        :secret_scanning_delegated_bypass_enabled,
        :secret_scanning_delegated_bypass_visible,
        :secret_scanning_delegated_bypass_enabled_by_security_configuration,
        :secret_scanning_delegated_bypass_disabled_by_security_configuration,

        :secret_scanning_delegated_closures_enabled,
        :secret_scanning_delegated_closures_enabled_by_organization,
        :secret_scanning_delegated_closures_visible,

        :has_mixed_restrictions,

        keyword_init: true
      ) do
        def initialize(
          update_security_products_settings_path: nil,
          update_repository_ghas_settings_path: nil,

          repository_security_configuration: nil,

          show_unarchived_features: false,

          dependency_graph_only_ghes_admin_toggle_allowed: false,
          dependency_graph_always_enabled_for_public_repos: false,
          dependency_graph_toggle_visible: false,
          dependency_graph_enabled: false,
          dependency_graph_toggle_allowed: false,
          dependency_graph_subtitle_prompt: nil,
          dependency_graph_disable_dependents_prompt: nil,
          dependency_graph_used_by_selection_view_model: false,
          dependency_graph_blocked_by_policy: false,

          dependency_graph_autosubmit_action_enabled: false,
          dependency_graph_autosubmit_action_use_labeled_runners: false,
          dependency_graph_autosubmit_action_visible: false,

          dependabot_alerts_auto_dismissal_learn_more_link: nil,
          dependabot_alerts_toggle_visible: false,
          dependabot_alerts_enabled: false,
          dependabot_alerts_blocked_by_policy: false,
          dependabot_alerts_configure_notifications_href: nil,
          dependabot_alerts_admin_configuration_prompt: nil,
          dependabot_alerts_disable_dependents_prompt: nil,
          dependabot_alerts_enable_prerequisites_prompt: nil,
          dependabot_alerts_custom_rules_toggle_visible: false,

          dependabot_security_updates_visible: false,
          dependabot_security_updates_toggle_visible: false,
          dependabot_security_updates_enabled: false,
          dependabot_security_updates_enable_prerequisites_prompt: nil,
          dependabot_security_updates_blocked_by_policy: false,
          dependabot_security_updates_admin_configuration_prompt: nil,

          dependabot_security_updates_grouping_visible: false,
          dependabot_security_updates_grouping_toggle_visible: false,
          dependabot_security_updates_grouping_enabled: false,
          dependabot_security_updates_grouping_prerequisites_prompt: nil,

          dependabot_on_actions_visible: false,
          dependabot_on_actions_toggle_visible: false,
          dependabot_on_actions_enabled: false,
          dependabot_on_actions_prerequisites_prompt: nil,

          dependabot_self_hosted_visible: false,
          dependabot_self_hosted_toggle_visible: false,
          dependabot_self_hosted_enabled: false,
          dependabot_self_hosted_prerequisites_prompt: nil,

          dependabot_autofix_visible: false,
          dependabot_autofix_enabled: false,
          dependabot_autofix_prerequisites_prompt: nil,

          dependabot_version_updates_visible: false,
          dependabot_version_updates_config_file_enabled: false,
          dependabot_version_updates_config_file_repository_path: nil,
          dependabot_version_updates_edit_config_href: nil,
          dependabot_version_updates_create_config_href: nil,
          dependabot_version_updates_using_fork_policy: nil,
          dependabot_version_updates_fork_status_visible: false,

          advanced_security_visible: false,
          advanced_security_enabled: false,
          advanced_security_license_prompt: nil,
          advanced_security_toggle_allowed: false,
          advanced_security_blocked_by_policy: false,
          advanced_security_blocked_by_in_progress_setting: false,
          advanced_security_show_blocked_by_policy_message: false,
          advanced_security_will_exceed_seat_allowance: false,
          advanced_security_blocked_by_seat_count_message: nil,
          advanced_security_billing_learn_more_href: nil,
          advanced_security_billed_repositories_description: nil,
          advanced_security_blocked_by_backfill: false,
          advanced_security_enablement_status: nil,
          advanced_security_blocked_by_turboghas_error: false,
          advanced_security_blocked_by_connect_error: false,

          code_scanning_enabled: false,
          code_scanning_default_setup_visible: false,
          code_scanning_default_setup_eligible: false,
          code_scanning_default_setup_user_has_enabled: false,
          code_scanning_default_setup_onboarding_status: nil,
          code_scanning_default_setup_active_suite: nil,
          code_scanning_default_setup_recommended_suite: "default",
          code_scanning_default_setup_public_scanning_visible: false,
          code_scanning_default_setup_prerequisite_error_message: nil,
          code_scanning_default_setup_blocked_by_in_progress_setting: false,

          secret_scanning_enabled: false,
          secret_scanning_public_scanning_enabled: false,
          secret_scanning_show_free_experience: false,
          secret_scanning_show_ghas_experience: false,
          secret_scanning_show_org_enablement_experience: false,
          secret_scanning_show_custom_patterns: false,
          secret_scanning_show_requires_ghas: false,
          secret_scanning_enabled_for_new_and_ghas_repos: false,
          secret_scanning_blocked_by_policy: false,
          secret_scanning_blocked_by_in_progress_setting: false,
          secret_scanning_enabled_for_instance: false,

          secret_scanning_push_protection_enabled: false,
          secret_scanning_push_protection_visible: false,
          secret_scanning_push_protection_blocked_by_policy: false,
          secret_scanning_push_protection_blocked_by_in_progress_setting: false,
          secret_scanning_push_protection_enabled_for_instance: false,

          secret_scanning_validity_checks_enabled: false,
          secret_scanning_validity_checks_visible: false,
          secret_scanning_validity_checks_blocked_by_policy: false,
          secret_scanning_validity_checks_enabled_for_instance: false,
          secret_scanning_validity_checks_enabled_by_owner: false,
          secret_scanning_validity_checks_enabled_by_business: false,
          secret_scanning_validity_checks_enabled_by_org: false,
          secret_scanning_validity_checks_blocked_by_in_progress_setting: false,
          secret_scanning_validity_checks_checkbox_disabled: false,

          secret_scanning_lower_confidence_patterns_enabled: false,
          secret_scanning_lower_confidence_patterns_visible: false,
          secret_scanning_lower_confidence_patterns_blocked_by_policy: false,
          secret_scanning_lower_confidence_patterns_enabled_by_owner: false,
          secret_scanning_lower_confidence_patterns_enabled_by_organization: false,
          secret_scanning_lower_confidence_patterns_enabled_by_enterprise: false,
          secret_scanning_lower_confidence_patterns_blocked_by_in_progress_setting: false,
          secret_scanning_lower_confidence_patterns_checkbox_disabled: false,

          secret_scanning_generic_secrets_enabled: false,
          secret_scanning_generic_secrets_visible: false,
          secret_scanning_generic_secrets_blocked_by_policy: false,
          secret_scanning_generic_secrets_enabled_by_owner: false,
          secret_scanning_generic_secrets_enabled_by_organization: false,
          secret_scanning_generic_secrets_enabled_by_enterprise: false,
          secret_scanning_generic_secrets_checkbox_disabled: false,
          secret_scanning_generic_secrets_blocked_by_in_progress_setting: false,

          secret_scanning_delegated_bypass_enabled: false,
          secret_scanning_delegated_bypass_visible: false,
          secret_scanning_delegated_bypass_enabled_by_security_configuration: false,
          secret_scanning_delegated_bypass_disabled_by_security_configuration: false,

         secret_scanning_delegated_closures_enabled: false,
         secret_scanning_delegated_closures_enabled_by_organization: false,
         secret_scanning_delegated_closures_visible: false,

          has_mixed_restrictions: false
          )
          super
        end
      end

      def initialize(data)
      end
    end
  end
end
