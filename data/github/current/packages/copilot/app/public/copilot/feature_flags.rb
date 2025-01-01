# typed: strict
# frozen_string_literal: true

module Copilot
  module FeatureFlags
    # these flags will be enabled by the setup-copilot script
    # they are alphabetized
    DEV_ENABLED = T.let(%w(
      code_referencing_dotcom
      copilot_a_chat
      copilot_g_chat
      copilot_access_seat_assignment_conversion_job
      copilot_api_max_pagination
      copilot_beta_features_opt_in
      copilot_block_go_client
      copilot_business_invitation_confirmation_job
      copilot_business_trial_job
      copilot_chat_custom_instructions
      copilot_chat_repo_custom_instructions
      copilot_chat_metrics
      copilot_chat_windows_terminal
      copilot_child_teams
      copilot_clean_usage_details_job
      copilot_coding_guidelines
      copilot_conversational_ux_embedding_update
      copilot_conversational_ux_history_refs
      copilot_custom_models
      copilot_dotcom_chat
      copilot_enabled_unconfigured
      copilot_engaged_oss_job
      copilot_enterprise_pr_summarization
      copilot_enterprise_team_job
      copilot_extension_access
      copilot_external_identity_job
      copilot_for_business
      copilot_for_business_csv_download
      copilot_for_enterprise
      copilot_for_enterprise_cli
      copilot_for_enterprise_dotcom_chat
      copilot_free_limited_user
      copilot_free_limited_user_token_quota
      copilot_free_token_refresh
      copilot_free_user_check_job
      copilot_free_user_coupon_check_job
      copilot_free_user_expired_email
      copilot_free_user_refresh_email
      copilot_free_user_warn_email
      copilot_immediate_cancellation_telemetry
      copilot_individual_trial_expiration_email_job
      copilot_knowledge_bases_fgp
      copilot_log_missing_editor_version
      copilot_mixed_licenses
      copilot_mobile_chat
      copilot_nes_signup
      copilot_next_edit_suggestions
      copilot_o1
      copilot_org_knowledge_bases_api
      copilot_org_transform_from_individual_job
      copilot_paid_user_free_check_job
      copilot_paid_user_free_check_job_refund
      copilot_prs_conversational_ux
      copilot_purchase_flow_refresh
      copilot_quota_testing
      copilot_seat_assignment_job
      copilot_seat_emission_job
      copilot_seat_history_check_job
      copilot_setting_get_started
      copilot_team_sync_job
      copilot_telemetry_language_update
      copilot_text_based_content_exclusions_api
      copilot_usage_details_job
      copilot_verbose_logging
      copilot_workspace
      copilot_workspace_signup
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
      content_exclusions_ga
      content_exclusions_old_flow
      copilot_a_chat
      copilot_g_chat
      copilot_access_seat_assignment_conversion_job
      copilot_allow_text_based_content_exclusions
      copilot_annotations
      copilot_api_max_pagination
      copilot_block_go_client
      copilot_business_invitation_confirmation_job
      copilot_business_trial_job
      copilot_dotcom_chat_ci_and_cb
      copilot_chat_custom_instructions
      copilot_chat_repo_custom_instructions
      copilot_chat_windows_terminal
      copilot_chatterbox
      copilot_child_teams
      copilot_clean_usage_details_job
      copilot_code_citations
      copilot_coding_guidelines
      copilot_communication_opt_out
      copilot_conversational_ux_embedding_update
      copilot_custom_models
      copilot_dotcom_chat
      copilot_enabled_unconfigured
      copilot_engaged_oss_job
      copilot_enterprise_pr_summarization
      copilot_extension_access
      copilot_external_identity_job
      copilot_for_business_csv_download
      copilot_for_business_free
      copilot_for_business_receipt_breakdown
      copilot_for_business_sign_up
      copilot_for_enterprise
      copilot_for_partners
      copilot_force_code_references
      copilot_free_limited_user
      copilot_free_limited_user_token_quota
      copilot_free_token_refresh
      copilot_free_user_blocked
      copilot_free_user_check_job
      copilot_free_user_coupon_check_job
      copilot_free_user_expired_email
      copilot_free_user_refresh_email
      copilot_free_user_warn_email
      copilot_immediate_cancellation_telemetry
      copilot_individual_trial_expiration_email_job
      copilot_insights_enabled
      copilot_log_missing_editor_version
      copilot_malware_filtering
      copilot_mixed_licenses
      copilot_mobile_chat
      copilot_nes_signup
      copilot_next_edit_suggestions
      copilot_o1
      copilot_org
      copilot_org_transform_from_individual_job
      copilot_organization_deduplicate_job
      copilot_paid_user_free_check_job
      copilot_paid_user_free_check_job_refund
      copilot_prs_conversational_ux
      copilot_purchase_flow_refresh
      copilot_quota_testing
      copilot_retrieval_alpha_org
      copilot_seat_assignment_job
      copilot_seat_emission_job
      copilot_seat_history_check_job
      copilot_show_csv_exports
      copilot_show_unconfigured_org_state
      copilot_sku_isolation_discovery
      copilot_sku_isolation_enforce_api
      copilot_sku_isolation_enforce_proxy
      copilot_snippy_load_test_enabled
      copilot_snippy_prompt_overlap
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
