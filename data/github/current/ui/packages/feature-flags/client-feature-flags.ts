// This list of feature flags will be preloaded on the server and available for use anywhere on the client.
// To access them, use the isFeatureEnabled function from @github-ui/feature-flags.

/**
 * JS Feature flags added to this list can be checked client-side with
 * `isFeatureEnabled('feature_name')` if they are enabled for the current user or globally.
 *
 * ## Good uses of client side feature flags
 *
 * * Testing a new JS library
 * * A/B testing UI changes
 * * Staff-shipping UI changes
 * * Enabling new UI to be rendered in a view
 *
 * ## Remember to enforce feature checks at the data access layer
 *
 * These feature flags can only prevent UI from displaying data, however,
 * they do not enforce access. Be sure to prevent changes and access to
 * data at the controller/model/API level to ensure any new data is
 * not exposed to the user.
 *
 * ## Flag names are visible to users
 *
 * Keep in mind that clients get the enabled flag names from the `<script
 * id="client-env" ...>` attribute - so if your feature is super
 * secret, consider giving it a non-obvious name (or maybe not using client
 * side code for it at all).
 *
 * Note: these flags are all automatically preloaded
 * @eslint-sort-array
 */
const jsFeatureFlags = [
  'ab_test_homepage_what_is_copilot_video',
  'actions_green_trees',
  'actions_matrix_output_improvements',
  'actions_number_type_dispatch_inputs',
  'alive_legacy_retries',
  'alternate_user_config_repo',
  'announcement_preference_hovercard',
  'api_insights_show_missing_data_banner',
  'appearance_settings',
  'arianotify_comprehensive_migration',
  'arianotify_partial_migration',
  'attestations_filtering',
  'attestations_sorting',
  'benchmark_mergebox',
  'billing_sku_level_budgets',
  'billingplatform_copilot_premium_sku',
  'browser_stats_disabled',
  'client_version_header',
  'code_scanning_security_configuration_ternary_state',
  'codespaces_prebuild_region_target_update',
  'contact_requests_implicit_opt_in',
  'contentful_lp_copilot_extensions',
  'contentful_lp_enterprise',
  'contentful_lp_flex_features',
  'contentful_lp_footnotes',
  'contentful_lp_form_phone_e164',
  'copilot_api_force_legacy_base_chat_model',
  'copilot_api_search_agent_skill',
  'copilot_api_tools_for_non_streaming_models',
  'copilot_auto_assign_metadata',
  'copilot_bing_search_use_azure_ai_agent_service',
  'copilot_bing_search_use_grounding_ui',
  'copilot_chat_attach_images',
  'copilot_chat_attach_multiple_images',
  'copilot_chat_attachments',
  'copilot_chat_autocomplete',
  'copilot_chat_custom_instructions',
  'copilot_chat_interview_survey',
  'copilot_chat_opening_thread_switch',
  'copilot_chat_repo_custom_instructions',
  'copilot_chat_repo_custom_instructions_preview',
  'copilot_chat_vision_in_claude',
  'copilot_chat_wholearea_dd',
  'copilot_client_dom_skills',
  'copilot_custom_copilots',
  'copilot_custom_copilots_feature_preview',
  'copilot_custom_copilots_org_owned',
  'copilot_custom_copilots_visibility',
  'copilot_delete_all_conversations',
  'copilot_dotcom_chat_file_upload',
  'copilot_duplicate_thread',
  'copilot_f2p_marketing_cta',
  'copilot_free_to_paid_telem',
  'copilot_ftp_settings_upgrade',
  'copilot_ftp_upgrade_to_pro_from_models',
  'copilot_ftp_your_copilot_settings',
  'copilot_header_button_to_immersive',
  'copilot_immersive_agent_sessions',
  'copilot_immersive_disable_draft_issue_ui',
  'copilot_immersive_draft_issue_persist_edited_issues_in_session',
  'copilot_immersive_draft_issue_template_required',
  'copilot_immersive_draft_issue_tree',
  'copilot_immersive_figma_integration',
  'copilot_immersive_issue_creation_cta',
  'copilot_immersive_issue_preview',
  'copilot_immersive_structured_model_picker',
  'copilot_issue_list_show_more',
  'copilot_metadata_poc',
  'copilot_new_conversation_starters',
  'copilot_new_immersive_references_ui',
  'copilot_no_floating_button',
  'copilot_paste_text_files',
  'copilot_pipes',
  'copilot_premium_request_quotas',
  'copilot_read_shared_conversation',
  'copilot_share_active_subthread',
  'copilot_share_forbidden_error',
  'copilot_show_deep_code_search_button',
  'copilot_showcase_icebreakers',
  'copilot_spaces_starters',
  'copilot_spark_single_user_iteration',
  'copilot_spark_use_billing_headers',
  'copilot_spark_use_streaming',
  'copilot_split_actions_enabled',
  'copilot_stable_subthreading_helpers',
  'copilot_staff_prompt_dialog',
  'copilot_swe_agent',
  'copilot_task_oriented_assistive',
  'copilot_task_oriented_assistive_prompts',
  'copilot_topics_as_references',
  'copilot_use_dom_page_context',
  'copilot_workbench',
  'copilot_workbench_cached_ai_panel',
  'copilot_workbench_connection_reload_banner',
  'copilot_workbench_debug_panel',
  'copilot_workbench_iterate_panel',
  'copilot_workbench_preview_analytics',
  'copilot_workbench_redirect',
  'copilot_workbench_refresh_on_wsod',
  'copilot_workbench_terminal',
  'copilot_workbench_user_limits',
  'copilot_workbench_vm_agent_attachments',
  'custom_copilots_128k_window',
  'custom_copilots_capi_mode',
  'custom_copilots_file_uploads',
  'custom_copilots_issues_prs',
  'dashboard_lists',
  'direct_to_salesforce',
  'disable_turbo_visit', // disables Turbo Drive
  'dnd_no_touch_device_check',
  'dotcom_chat_client_side_skills',
  'fgpat_permissions_selector_redesign',
  'ghost_pilot_confidence_truncation_25',
  'ghost_pilot_confidence_truncation_40',
  'ghost_pilot_confidence_truncation_55',
  'ghost_pilot_confidence_truncation_70',
  'ghost_pilot_debug_panel',
  'ghost_pilot_dotcom_fallback',
  'ghost_pilot_pr_autocomplete_comments',
  'ghost_pilot_vnext',
  'github_models_scheduled_hydro_events',
  'hypersight',
  'insert_before_patch', // Enables the insertBefore patch for React.
  'issues_react_blur_item_picker_on_close',
  'issues_react_create_issue_with_copilot_cta',
  'issues_react_create_milestone',
  'issues_react_include_bots_in_pickers',
  'issues_react_index_quick_filters',
  'issues_react_prohibit_title_fallback',
  'issues_react_remove_labels_loading',
  'issues_react_remove_placeholders',
  'lifecycle_label_name_updates',
  'link_contact_sales_swp_marketo',
  'mardown_editor_use_on_input',
  'marketing_pages_search_explore_provider',
  'memex_mwl_filter_field_delimiter',
  'memex_roadmap_drag_style',
  'nonreporting_relay_graphql_status_codes',
  'notifyd_enable_issue_thread_subscriptions',
  'notifyd_issue_watch_activity_notify',
  'primer_live_region_element',
  'primer_primitives_experimental',
  'primer_react_action_list_item_as_button', // enables using buttons in action list items in Primer React
  'primer_react_css_modules_ga', // enables CSS Modules in Primer React for everyone
  'primer_react_css_modules_staff', // enables CSS Modules in Primer React for staff
  'primer_react_overlay_overflow', // enables responsive overlay with width overflows
  'primer_react_segmented_control_tooltip', // enables tooltip on SegmentedControl.IconButton
  'primer_react_select_panel_fullscreen_on_narrow',
  'primer_react_select_panel_order_selected_at_top', // displays the selected items at the top of the list in the Primer React SelectPanel
  'primer_react_select_panel_with_modern_action_list', // enables modern ActionList for SelectPanel
  'react_quality_profiling',
  'remove_child_patch', // Enables the removeChild patch for React.
  'report_hydro_web_vitals', // controls whether to report web vitals to Hydro
  'repository_suggester_elastic_search',
  'sample_network_conn_type',
  'scheduled_reminders_updated_limits',
  'send_app_type_header',
  'site_homepage_contentful',
  'site_msbuild_hide_integrations', // controls whether to hide the integrations section even if Contentful data is present
  'site_msbuild_launch',
  'site_msbuild_webgl_hero',
  'spark_auth_token_endpoint',
  'spark_commit_on_default_branch',
  'spark_unlimited_dev_compute',
  'spark_update_user_edit_status',
  'swp_enterprise_contact_form',
  'tasklist_block',
  'use_copilot_avatar',
  'use_paginated_org_picker_cost_center_form',
  'use_paginated_repo_picker_cost_center_form',
  'viewscreen_sandbox',
  'workbench_default_sonnet4',
  'workbench_store_readonly',
  'workspace_editor_fix_a_build_function_calling',
] as const

/**
 * If the feature flag you want to use is not in this list, please add it in
 * ui/packages/feature-flags/client-feature-flags.ts
 */
export type JSFeatureFlag = (typeof jsFeatureFlags)[number]

/**
 * CSS feature flags can be used in any scss/css file like this:
 *
 * [data-css-features~="my_feature_flag" i] {
 *  // styles behind flag
 * }
 *
 * Note: these flags are all automatically preloaded
 * @eslint-sort-array
 */
const cssFeatureFlags = ['prs_diff_containment'] as const

/**
 * If the feature flag you want to use is not in this list, please add it in
 * ui/packages/feature-flags/client-feature-flags.ts
 */
export type CSSFeatureFlag = (typeof cssFeatureFlags)[number]

// Export separately from definition to support the eslint-sort-array rule
export {cssFeatureFlags, jsFeatureFlags}
