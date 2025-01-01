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
      :ab_test_homepage_what_is_copilot_video,
      :actions_green_trees,
      :actions_matrix_output_improvements,
      :actions_number_type_dispatch_inputs,
      :announcement_preference_hovercard,
      :arianotify_comprehensive_migration,
      :arianotify_partial_migration,
      :benchmark_mergebox,
      :billing_platform_lfs_enabled,
      :browser_stats_disabled,
      :bypass_trusted_types_policy_checks,
      :copilot_immersive_file_preview,
      :copilot_immersive_title_favicon,
      :copilot_load_latest_thread,
      :copilot_new_references_ui,
      :copilot_staff_prompt_dialog,
      :copilot_byok,
      :copilot_beta_features_opt_in,
      :copilot_chat_custom_instructions,
      :copilot_chat_repo_custom_instructions,
      :copilot_chat_follow_up_thread_suggestions,
      :copilot_chat_generate_thread_suggestions,
      :copilot_chat_magic_kbs,
      :copilot_chat_static_thread_suggestions,
      :copilot_conversational_ux_embedding_update,
      :copilot_conversational_ux_history_refs,
      :copilot_chat_improved_code_blocks,
      :copilot_implicit_context,
      :copilot_issue_creation,
      :copilot_react_markdown,
      :copilot_reviews,
      :copilot_semantic_code_search_settings,
      :copilot_smell_icebreaker_ux,
      :copilot_split_actions_enabled,
      :copilot_summary_beta,
      :drag_and_drop_experimental_move_dialog,
      :disable_turbo_visit, # disables Turbo Drive
      :experimentation_azure_variant_endpoint,
      :failbot_handle_non_errors,
      :geojson_azure_maps,
      :ghost_pilot_confidence_truncation_25,
      :ghost_pilot_confidence_truncation_40,
      :ghost_pilot_confidence_truncation_55,
      :ghost_pilot_confidence_truncation_70,
      :ghost_pilot_debug_panel,
      :ghost_pilot_pr_autocomplete_comments,
      :ghost_pilot_vnext,
      :hadron_terminal_completions,
      :hovercard_accessibility,
      :issues_advanced_search,
      :issues_advanced_search_has_filter,
      :issues_react_close_as_duplicate,
      :issues_react_combined_template_list,
      :issues_react_new_timeline,
      :issues_react_avatar_refactor,
      :issues_react_remove_placeholders,
      :issues_react_blur_item_picker_on_close,
      :issues_react_index_quick_filters,
      :kb_source_repos,
      :marketing_pages_search_explore_provider,
      :primer_live_region_element,
      :primer_react_action_list_item_as_button, # enables using buttons in action list items in Primer React
      :primer_react_css_modules_ga, # enables CSS Modules in Primer React for everyone
      :primer_react_css_modules_staff, # enables CSS Modules in Primer React for staff
      :primer_react_css_modules_team, # enables CSS Modules in Primer React for the team
      :primer_react_select_panel_with_modern_action_list, # enables modern ActionList for SelectPanel
      :primer_react_overlay_overflow, # enables responsive overlay with width overflows
      :prx,
      :pwa,
      :react_keyboard_shortcuts_dialog,
      :remove_child_patch, # Enables the removeChild patch for React.
      :report_hydro_web_vitals, # controls whether to report web vitals to Hydro
      :repository_suggester_elastic_search,
      :sample_network_conn_type,
      :site_metered_billing_update,
      :tasklist_block,
      :issues_react_close_as_duplicate,
      :issues_react_remove_labels_loading,
      :ignore_hidden_in_quote_reply,
      :textarea_field_sizing,
      :lifecycle_label_name_updates,
      :issues_react_customise_notifications_ui,
      :notifyd_issue_watch_activity_notify,
      :notifyd_enable_issue_thread_subscriptions,
    ]

    CSS_FLAGS = [
      :textarea_field_sizing
    ]
  end
end
