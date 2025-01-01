/**
 * FEATURE FLAGS (aka "Flippers")
 * =================
 * These are flagged-in features that we control.
 * To manage these features, go to: https://devportal.githubapp.com/feature-flags
 */
export const clientFeatureFlags = [
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

  // Enables the resync index button for project admins for reindexing Elasticsearch for Memex Without limits
  'memex_resync_index',

  // Controls whether automations are enabled or not, this is not a real FF, it delegates to enterprise business config
  'memex_automation_enabled',

  // Enable Table View Without Limits (Elasticsearch powered backend)
  'memex_table_without_limits',

  // Disable file upload in the side-panel for draft issues
  'memex_disable_draft_issue_file_upload',

  // Disable autofocusing first item in project views
  'memex_disable_autofocus',

  // Enable project status updates
  'memex_status_updates_notifications',

  // ensures that the projects classic UI is enabled
  'projects_classic_sunset_override',

  //Improve rendering performance of PWL table view
  'memex_mwl_table_cell_perf',

  // Update the labels picker to not have a loading state and cache the results better
  'issues_react_remove_labels_loading',

  // Enable the create milestone button in the milestone picker
  'issues_react_create_milestone',

  // Make issue creation the default omnibar action instead of draft creation
  'memex_omnibar_prioritize_create_issue',

  // Disable the custom notification subscription UI in Issues React for users who use Newsies (instead of Notifyd)
  'notifyd_issue_watch_activity_notify',
  'notifyd_enable_issue_thread_subscriptions',

  // Adjust the UI styling to improve accessibility on small viewports
  'memex_small_viewport_a11y',

  // Handle case where feature flags are out of sync between client and server
  'memex_flag_sync_error_handling',

  // Enable dnd-kit's touch-specific dragging so that in board view, users can both scroll and drag on a touch device
  'memex_touch_to_drag',

  // Enable the new issue dependencies UI in Issues React
  'issue_dependencies',

  // Enable primer styling for picker-list
  'primer_react_select_panel_with_modern_action_list',

  // Enable internal dev features for issue dependencies
  'issue_dependencies_internal_dev',

  // Enable the new column menu options for moving columns
  'memex_column_menu_position',
]

export const projectActorFeatureFlags = [
  // Enable Table View Without Limits (Elasticsearch powered backend)
  'memex_table_without_limits',
]

export const featureFlags = [...clientFeatureFlags, ...projectActorFeatureFlags] as const

export type ClientFeatureFlags = (typeof clientFeatureFlags)[number]
export type ProjectActorFeatureFlags = (typeof projectActorFeatureFlags)[number]
export type FeatureFlags = (typeof featureFlags)[number]

/**
 * FEATURE PREVIEWS
 * =================
 * These are opt-in features available to users.
 * To manage these features, go to: https://admin.github.com/devtools/toggleable_features
 */
export const featurePreviews = [] as const

export type FeaturePreviews = (typeof featurePreviews)[number]

/**
 * FEATURE GATES
 * =================
 * These are features gated by the billing plan of the memex owner org/user.
 * Feature gates are specified in plans.yaml files, as described here:
 * https://github.com/github/githubber-content/blob/691749f4be532371dbb7aa65a8b2440e68f6e673/docs/technology/dotcom/plan-feature-gates.md
 */
export const featureGates = [
  // Enables basic features for creating/saving custom, current state charts in the project insights view for public projects
  'memex_charts_basic_public',
  // Enables basic features for creating/saving custom, current state charts in the project insights view for private projects
  'memex_charts_basic_private',
  // Enables basic features for viewing/creating/saving historical Insights charts in the project insights view for public projects
  'memex_insights_basic_public',
  // Enables basic features for viewing/creating/saving historical Insights charts in the project insights view for private projects
  'memex_insights_basic_private',
] as const

export type FeatureGates = (typeof featureGates)[number]

/**
 * ENABLED FEATURES
 * =================
 * Projects don't need to know where a feature is enabled from, only the state.
 * Given that, we merge all feature flags, previews, and gates into a single array.
 */
export type EnabledFeatures = FeaturePreviews | FeatureFlags | FeatureGates
export const enabledFeatures = [...featurePreviews, ...featureFlags, ...featureGates]

export type EnabledFeaturesMap = {[P in EnabledFeatures]: boolean}

export const allFeaturesDisabled = enabledFeatures.reduce((map, current) => {
  map[current] = false
  return map
}, {} as EnabledFeaturesMap)
