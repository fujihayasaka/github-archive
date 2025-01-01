/**
 * FEATURE FLAGS (aka "Flippers")
 * =================
 * These are flagged-in features that we control.
 * To manage these features, go to: https://devportal.githubapp.com/feature-flags
 */
const featureFlags = [
  // This method demonstrates usage of this service, but it isn't a real feature.
  'memex_beta_with_dummy_feature',

  // Enables access to the Insights tab/view from the navigation buttons,
  // and enables historical Insights 'time' charts
  'memex_insights',

  // Feature flag override to provide memex_charts_basic_public/private gated features
  // typically reserved for paid plans.
  'memex_charts_basic_allow',

  // Whether to show the Group by assignees, milestones for historical charts
  'memex_historical_charts_on_assignees_milestones',

  // Tasks list block gate the tracks column and all things related to hierarchy
  'tasklist_block',

  // Enable "group by distinct" for multi-value fields like assignees
  'memex_group_by_multi_value_changes',

  // Enables the redesigned tracked by pills and hovercards
  'tasklist_tracked_by_redesign',

  // Enables a paginated archive view to support a 48K archive limit
  // The memex_table_without_limits feature flag will also enable the paginated archive view
  'memex_paginated_archive',

  // Enables the resync index button for project admins for reindexing Elasticsearch for Memex Without limits
  'memex_resync_index',

  // Controls whether automations are enabled or not, this is not a real FF, it delegates to enterprise business config
  'memex_automation_enabled',

  // Enable Table View Without Limits (Elasticsearch powered backend)
  'memex_table_without_limits',

  // Enable experimental move dialog in Memex's table view
  'memex_table_experimental_move_dialog',

  // Enable experimental move dialog for Memex's tabs
  'memex_tab_experimental_move_dialog',

  // Disable file upload in the side-panel for draft issues
  'memex_disable_draft_issue_file_upload',

  // Disable autofocusing first item in project views
  'memex_disable_autofocus',

  // Enable the issue_types picker in the issue create dialog
  'issue_types',

  // Enable project status updates
  'memex_status_updates_notifications',

  // Display the sub-issues list and button group
  'sub_issues',

  // Enable the beta optout controls
  'mwl_beta_optout',

  // Enable display of validation messages for filter bar in mwl
  'mwl_filter_bar_validation',

  // Enable sticky board columns that stay rendered while loading new items in MWL
  'memex_mwl_sticky_board_columns',

  // Calculate field aggregations on the server for PWL
  'memex_mwl_field_aggregations',

  // disables the projects classic UI
  'projects_classic_sunset_ui',

  // ensures that the projects classic UI is enabled
  'projects_classic_sunset_override',

  // Enable the new issue viewer for logged out users
  'issues_react_logged_out',

  // Enable Insights charts without any feature restrictions based on org/user/free/paid/private/public
  'memex_charts_for_all',

  // Use dedicated side panel query
  'memex_side_panel_query',

  // Write to Elasticsearch synchronously the user updates a field value in MySQL.
  'memex_sync_write_to_es',

  // Show unique column values as filter suggestions for MWL projects
  'memex_mwl_unique_filter_suggestions',

  //Improve rendering performance of PWL table view
  'memex_mwl_table_cell_perf',

  // Log warnings for timeline validation issues in the issue viewer
  'issues_react_validate_timeline_items',

  // Update the labels picker to not have a loading state and cache the results better
  'issues_react_remove_labels_loading',

  // Enable the create milestone button in the milestone picker
  'issues_react_create_milestone',

  // Enable server-side table without limits CSV exports (Elasticsearch powered backend)
  'memex_table_without_limits_csv_export',

  // Make issue creation the default omnibar action instead of draft creation
  'memex_omnibar_prioritize_create_issue',

  // Enable the Insights charts view and API for Memex Without Limits
  'memex_mwl_insights',

  // Disable the custom notification subscription UI in Issues React for users who use Newsies (instead of Notifyd)
  'notifyd_issue_watch_activity_notify',
  'notifyd_enable_issue_thread_subscriptions',

  // Adjust the UI styling to improve accessibility on small viewports
  'memex_small_viewport_a11y',

  // Whether to use the v7 start transition react-router flag for memex startup
  'memex_v7_start_transition',

  // Handle case where feature flags are out of sync between client and server
  'memex_flag_sync_error_handling',

  // Use the standard TypeFilterProvider instead of MemexTypeFilterProvider
  'memex_mwl_use_type_provider',

  // Invalidate client cache when a field's settings change
  'memex_mwl_refresh_groups',

  // Disable use of the sticky header observer
  'issues_react_disable_sticky_header_observer',

  // Bypass template selection when we have only one template
  'issues_react_bypass_template_selection',

  // Enable grouped diffs on comment edit history
  'issues_react_grouped_diff_on_edit_history',
] as const

type FeatureFlags = (typeof featureFlags)[number]

/**
 * FEATURE PREVIEWS
 * =================
 * These are opt-in features available to users.
 * To manage these features, go to: https://admin.github.com/devtools/toggleable_features
 */
const featurePreviews = [] as const

type FeaturePreviews = (typeof featurePreviews)[number]

/**
 * FEATURE GATES
 * =================
 * These are features gated by the billing plan of the memex owner org/user.
 * Feature gates are specified in plans.yaml files, as described here:
 * https://github.com/github/githubber-content/blob/691749f4be532371dbb7aa65a8b2440e68f6e673/docs/technology/dotcom/plan-feature-gates.md
 */
const featureGates = [
  // Enables basic features for creating/saving custom, current state charts in the project insights view for public projects
  'memex_charts_basic_public',
  // Enables basic features for creating/saving custom, current state charts in the project insights view for private projects
  'memex_charts_basic_private',
  // Enables basic features for viewing/creating/saving historical Insights charts in the project insights view for public projects
  'memex_insights_basic_public',
  // Enables basic features for viewing/creating/saving historical Insights charts in the project insights view for private projects
  'memex_insights_basic_private',
] as const

type FeatureGates = (typeof featureGates)[number]

/**
 * ENABLED FEATURES
 * =================
 * Projects don't need to know where a feature is enabled from, only the state.
 * Given that, we merge all feature flags, previews, and gates into a single array.
 */
// eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
export type EnabledFeatures = FeaturePreviews | FeatureFlags | FeatureGates
export const enabledFeatures = [...featurePreviews, ...featureFlags, ...featureGates]

export type EnabledFeaturesMap = {[P in EnabledFeatures]: boolean}

export const allFeaturesDisabled = enabledFeatures.reduce((map, current) => {
  map[current] = false
  return map
}, {} as EnabledFeaturesMap)
