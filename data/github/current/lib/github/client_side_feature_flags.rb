# typed: true
# frozen_string_literal: true

module GitHub
  module ClientSideFeatureFlags
    # Feature flags added to the list below can be checked client-side by
    # `isFeatureEnabled("UPPERCASE_FEATURE_NAME")` if they are enabled on the
    # current context.
    #
    # ## Good uses of client side feature flags
    #
    # * Testing a new JS library
    # * A/B testing UI changes
    # * Staff-shipping UI changes
    # * Enabling new UI to be rendered in a view
    #
    # ## Remember to enforce feature checks at the data access layer
    #
    # These feature flags can only prevent UI from displaying data, however,
    # they do not enforce access. Be sure to prevent changes and access to
    # data at the controller/model/API level to ensure any new data is
    # not exposed to the user.
    #
    # ## Flag names are visible to users
    #
    # Keep in mind that clients get the enabled flag names from the `<script
    # id="client-env" ...>` attribute - so if your feature is super
    # secret, consider giving it a non-obvious name (or maybe not using client
    # side code for it at all).
    #
    # Note: these flags are all automatically preloaded

    FLAGS = [
      :a11y_quote_reply_fix,
      :ab_test_homepage_what_is_copilot_video,
      :actions_green_trees,
      :actions_matrix_output_improvements,
      :actions_number_type_dispatch_inputs,
      :alive_legacy_retries,
      :allow_subscription_halted_error,
      :announcement_preference_hovercard,
      :arianotify_comprehensive_migration,
      :arianotify_partial_migration,
      :benchmark_mergebox,
      :browser_stats_disabled,
      :bypass_trusted_types_policy_checks,
      :contentful_lp_optimize_image,
      :contentful_lp_hero_video_cover_image,
      :copilot_api_tools_for_non_streaming_models,
      :copilot_new_immersive_references_ui,
      :copilot_immersive_issue_preview,
      :copilot_immersive_figma_integration,
      :copilot_new_references_ui,
      :copilot_pipes,
      :copilot_workbench,
      :copilot_staff_prompt_dialog,
      :copilot_chat_interview_survey,
      :copilot_client_dom_skills,
      :copilot_chat_ambient_error_banner,
      :copilot_chat_attach_images,
      :copilot_chat_custom_instructions,
      :copilot_chat_repo_custom_instructions,
      :copilot_chat_repo_custom_instructions_preview,
      :copilot_chat_immersive_subthreading,
      :copilot_chat_show_model_picker_on_retry,
      :copilot_chat_opening_thread_switch,
      :copilot_custom_copilots,
      :copilot_dotcom_chat_file_upload,
      :copilot_delete_all_conversations,
      :copilot_no_floating_button,
      :copilot_reviews,
      :copilot_smell_icebreaker_ux,
      :copilot_split_actions_enabled,
      :copilot_ui_refs,
      :copilot_topics_as_references,
      :copilot_read_shared_conversation,
      :copilot_duplicate_thread,
      :copilot_share_active_subthread,
      :copilot_buffered_streaming,
      :copilot_overages_usage_report,
      :dotcom_chat_client_side_skills,
      :disable_turbo_visit, # disables Turbo Drive
      :experimentation_azure_variant_endpoint,
      :failbot_handle_non_errors,
      :geojson_azure_maps,
      :ghost_pilot_confidence_truncation_25,
      :ghost_pilot_confidence_truncation_40,
      :ghost_pilot_confidence_truncation_55,
      :ghost_pilot_confidence_truncation_70,
      :ghost_pilot_debug_panel,
      :ghost_pilot_dotcom_fallback,
      :ghost_pilot_pr_autocomplete_comments,
      :ghost_pilot_vnext,
      :github_models_gateway,
      :github_models_o3_mini_streaming,
      :hadron_terminal_completions,
      :hovercard_accessibility,
      :hypersight,
      :insert_before_patch, # Enables the insertBefore patch for React.
      :issues_advanced_search,
      :issues_advanced_search_has_filter,
      :issues_react_validate_timeline_items,
      :issues_react_remove_placeholders,
      :issues_react_blur_item_picker_on_close,
      :issues_react_index_quick_filters,
      :issues_react_include_bots_in_pickers,
      :kb_source_repos,
      :marketing_pages_search_explore_provider,
      :primer_live_region_element,
      :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
      :primer_react_css_modules_ga, # enables CSS Modules in Primer React for everyone
      :primer_react_css_modules_staff, # enables CSS Modules in Primer React for staff
      :primer_react_select_panel_with_modern_action_list, # enables modern ActionList for SelectPanel
      :primer_react_overlay_overflow, # enables responsive overlay with width overflows
      :primer_react_segmented_control_tooltip, # enables tooltip on SegmentedControl.IconButton
      :prx,
      :pwa,
      :react_data_router_pull_requests,
      :remove_child_patch, # Enables the removeChild patch for React.
      :report_hydro_web_vitals, # controls whether to report web vitals to Hydro
      :repository_suggester_elastic_search,
      :sample_network_conn_type,
      :swp_enterprise_contact_form,
      :site_copilot_page_brand_template,
      :site_copilot_plans_ga,
      :site_proxima_australia_update,
      :tasklist_block,
      :viewscreen_sandbox,
      :issues_react_remove_labels_loading,
      :issues_react_create_milestone,
      :issues_react_new_select_panel,
      :copilot_auto_assign_metadata,
      :issues_react_cache_fix_workaround,
      :ignore_hidden_in_quote_reply,
      :lifecycle_label_name_updates,
      :notifyd_issue_watch_activity_notify,
      :notifyd_enable_issue_thread_subscriptions,
      :item_picker_new_select_panel,
      :copilot_task_oriented_assistive,
      :copilot_task_oriented_assistive_prompts,
      :mardown_editor_use_on_input,
      :workspace_editor_fix_a_build_function_calling,
      :issues_react_assignee_warning,
      :issue_types_prevent_private_type_creation,
      :issues_react_grouped_diff_on_edit_history,
      :use_paginated_organization_picker,
      :copilot_spaces_edit_experience,
      :issues_react_bypass_template_selection,
    ]

    CSS_FLAGS = [
      :the_prs_cascade_containment_integration,
    ]
  end
end
