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

    FLAGS = [
      :ab_test_homepage_what_is_copilot_video,
      :actions_green_trees,
      :actions_matrix_output_improvements,
      :actions_number_type_dispatch_inputs,
      :arianotify_comprehensive_migration,
      :arianotify_partial_migration,
      :benchmark_mergebox,
      :billing_platform_lfs_enabled,
      :browser_stats_disabled,
      :bypass_trusted_types_policy_checks,
      :code_vulnerability_scanning,
      :copilot_floating_button,
      :copilot_beta_features_opt_in,
      :copilot_chat_conversation_intent_knowledge_search_skill,
      :copilot_chat_custom_instructions,
      :copilot_chat_follow_up_thread_suggestions,
      :copilot_chat_generate_thread_suggestions,
      :copilot_chat_static_thread_suggestions,
      :copilot_completion_new_domain,
      :copilot_conversational_ux_embedding_update,
      :copilot_conversational_ux_history_refs,
      :copilot_copy_message,
      :copilot_followup_to_agent,
      :copilot_format_diff,
      :copilot_implicit_context,
      :copilot_issue_creation,
      :copilot_react_markdown,
      :copilot_reviews,
      :copilot_semantic_code_search_settings,
      :copilot_smell_icebreaker_ux,
      :copilot_split_actions_enabled,
      :custom_inp,
      :disable_turbo_visit,
      :experimentation_azure_variant_endpoint,
      :failbot_handle_non_errors,
      :filter_prefetch_suggestions,
      :geojson_azure_maps,
      :ghost_pilot_confidence_truncation,
      :ghost_pilot_confidence_truncation_25,
      :ghost_pilot_confidence_truncation_40,
      :ghost_pilot_debug_panel,
      :ghost_pilot_div,
      :ghost_pilot_pr_autocomplete_comments,
      :ghost_pilot_stream_handling,
      :ghost_pilot_undo_fix,
      :ghost_pilot_vnext,
      :hadron_terminal_completions,
      :hovercard_accessibility,
      :hovercard_longer_activate_timeout,
      :issues_advanced_search,
      :kb_source_repos,
      :marketing_pages_search_explore_provider,
      :primer_live_region_element,
      :primer_react_action_list_item_as_button,
      :primer_react_css_modules_ga,
      :primer_react_css_modules_staff,
      :primer_react_css_modules_team,
      :prx,
      :pwa,
      :react_keyboard_shortcuts_dialog,
      :remove_child_patch,
      :report_hydro_web_vitals,
      :repository_suggester_elastic_search,
      :sample_network_conn_type,
      :site_metered_billing_update,
      :tasklist_block,
      :turbo_experiment_risky,
    ]
  end
end
