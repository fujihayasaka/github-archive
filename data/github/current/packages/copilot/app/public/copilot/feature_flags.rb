# typed: strict
# frozen_string_literal: true

module Copilot
  module FeatureFlags
    # these flags will be enabled by the setup-copilot script
    # they are alphabetized
    DEV_ENABLED = T.let(%w(
      code_referencing_dotcom
      copilot_a_f
      copilot_access_seat_assignment_conversion_job
      copilot_activity_api
      copilot_api_max_pagination
      copilot_basic_enterprise_access_reinstatement_job
      copilot_block_python_user_agent
      copilot_business_invitation_confirmation_job
      copilot_business_trial_job
      copilot_chat_attachments
      copilot_chat_custom_instructions
      copilot_chat_immersive_subthreading
      copilot_chat_metrics
      copilot_chat_repo_custom_instructions
      copilot_chat_show_model_picker_on_retry
      copilot_chat_store_model_in_messages
      copilot_chat_subthreads_backend
      copilot_chat_windows_terminal
      copilot_child_teams
      copilot_clean_usage_details_job
      copilot_code_guidelines_occurrences_page
      copilot_coding_guidelines
      copilot_custom_models
      copilot_desktop
      copilot_dotcom_chat
      copilot_enabled_unconfigured
      copilot_engaged_oss_job
      copilot_enterprise_info_endpoint
      copilot_enterprise_pr_summarization
      copilot_enterprise_seat_deduplicate_job
      copilot_enterprise_team_job
      copilot_expanded_policies_in_details_api
      copilot_extension_access
      copilot_external_identity_job
      copilot_for_business
      copilot_for_business_csv_download
      copilot_for_enterprise
      copilot_for_enterprise_cli
      copilot_for_enterprise_dotcom_chat
      copilot_free_cli
      copilot_free_desktop
      copilot_free_mobile
      copilot_free_token_refresh
      copilot_free_user_check_job
      copilot_free_user_coupon_check_job
      copilot_free_user_expired_email
      copilot_free_user_refresh_email
      copilot_free_user_warn_email
      copilot_individual_trial_expiration_email_job
      copilot_mobile_chat
      copilot_nes_signup
      copilot_next_edit_suggestions
      copilot_no_floating_button
      copilot_o_f
      copilot_o_ff
      copilot_o1
      copilot_org_access_reinstatement_job
      copilot_org_transform_from_individual_job
      copilot_overages
      copilot_paid_user_free_check_job
      copilot_paid_user_free_check_job_refund
      copilot_prs_conversational_ux
      copilot_quota_testing
      copilot_respect_revokable_access
      copilot_revokable_access
      copilot_seat_assignment_job
      copilot_seat_emission_job
      copilot_seat_history_check_job
      copilot_setting_get_started
      copilot_staff_prompt_dialog
      copilot_task_oriented_assistive
      copilot_task_oriented_assistive_mode
      copilot_task_oriented_assistive_prompts
      copilot_team_sync_job
      copilot_telemetry_language_update
      copilot_text_based_content_exclusions_api
      copilot_usage_details_job
      copilot_verbose_logging
      copilot_workspace
      copilot_workspace_signup
      copilot-code-reviews-emit-guideline-id
      enable_usage_metrics_ent_team_endpoint
      enable_usage_metrics_team_endpoint
      enterprise_validate_copilot_azure_subscription
      failbot_handle_non_errors
    ), T::Array[String])

    # These flags will be enabled by the CopilotTestHelper, disable them explicitly in tests
    # these will be created by the setup-copilot script for dev
    TEST_ENABLED = T.let(%w(
      copilot_mail_logger
    ), T::Array[String])

    # These flags will be disabled by the CopilotTestHelper, enable them explicitly in tests
    # these will be created by the setup-copilot script for dev but not enabled unless they also exist in DEV_ENABLED
    # they are alphabetized
    TEST_DISABLED = T.let(%w(
      blackbird_use_v2_mw
      codespaces_copilot_demo_repository
      codespaces_copilot_demo_template
      copilot_access_seat_assignment_conversion_job
      copilot_activity_api
      copilot_allow_text_based_content_exclusions
      copilot_annotations
      copilot_api_max_pagination
      copilot_basic_enterprise_access_reinstatement_job
      copilot_block_python_user_agent
      copilot_business_invitation_confirmation_job
      copilot_business_trial_job
      copilot_chat_custom_instructions
      copilot_chat_repo_custom_instructions
      copilot_chat_windows_terminal
      copilot_chatterbox
      copilot_child_teams
      copilot_clean_usage_details_job
      copilot_code_citations
      copilot_code_guidelines_occurrences_page
      copilot_coding_guidelines
      copilot_communication_opt_out
      copilot_custom_models
      copilot_custom_models_multi_ft
      copilot_desktop
      copilot_dotcom_chat
      copilot_enabled_unconfigured
      copilot_engaged_oss_job
      copilot_enterprise_pr_summarization
      copilot_enterprise_seat_deduplicate_job
      copilot_extension_access
      copilot_external_identity_job
      copilot_for_business_csv_download
      copilot_for_business_free
      copilot_for_business_receipt_breakdown
      copilot_for_business_sign_up
      copilot_for_enterprise
      copilot_for_partners
      copilot_force_code_references
      copilot_free_cli
      copilot_free_desktop
      copilot_free_mobile
      copilot_free_token_refresh
      copilot_free_user_blocked
      copilot_free_user_check_job
      copilot_free_user_coupon_check_job
      copilot_free_user_expired_email
      copilot_free_user_refresh_email
      copilot_free_user_warn_email
      copilot_individual_trial_expiration_email_job
      copilot_insights_enabled
      copilot_malware_filtering
      copilot_mobile_chat
      copilot_nes_signup
      copilot_next_edit_suggestions
      copilot_o1
      copilot_org
      copilot_org_access_reinstatement_job
      copilot_org_transform_from_individual_job
      copilot_organization_deduplicate_job
      copilot_overages
      copilot_paid_user_free_check_job
      copilot_paid_user_free_check_job_refund
      copilot_prs_conversational_ux
      copilot_quota_testing
      copilot_respect_revokable_access
      copilot_retrieval_alpha_org
      copilot_revokable_access
      copilot_seat_assignment_job
      copilot_seat_emission_job
      copilot_seat_history_check_job
      copilot_show_csv_exports
      copilot_sku_isolation_discovery
      copilot_sku_isolation_enforce_api
      copilot_sku_isolation_enforce_proxy
      copilot_snippy_load_test_enabled
      copilot_snippy_prompt_overlap
      copilot_staff_prompt_dialog
      copilot_task_oriented_assistive
      copilot_task_oriented_assistive_mode
      copilot_task_oriented_assistive_prompts
      copilot_telemetry_language_update
      copilot_text_based_content_exclusions_api
      copilot_token_include_network_information
      copilot_usage_details_job
      copilot_verbose_logging
      copilot_vsc_electron_fetcher
      copilot_workspace
      copilot_workspace_signup
      copilot_xcode
      copilot_xcode_chat
      orca_full_file_extensions_validation
    ), T::Array[String])

    ALL_FLAGS = T.let((DEV_ENABLED.to_set + TEST_ENABLED.to_set + TEST_DISABLED.to_set), T::Set[String])
  end
end
