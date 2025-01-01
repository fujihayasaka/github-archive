export const DashboardDismissalSettings = {
  Playlist: 'nux_dashboard_playlist_dismissed',
  GettingStarted: 'nux_dashboard_getting_started_dismissed',
  Docs: 'nux_dashboard_docs_dismissed',
  Recommendations: 'nux_dashboard_recommendations_dismissed',
  VSCode: 'nux_dashboard_vscode_dismissed',
  Desktop: 'nux_dashboard_desktop_dismissed',
} as const

export const GettingStartedChecklistSettings = {
  CustomizedAccount: 'new_user_has_customized_account',
  TriedCopilot: 'new_user_has_tried_copilot',
  CreatedRepo: 'new_user_has_created_repo',
} as const

export type DashboardDismissalSettings = (typeof DashboardDismissalSettings)[keyof typeof DashboardDismissalSettings]
export type GettingStartedChecklistSettings =
  (typeof GettingStartedChecklistSettings)[keyof typeof GettingStartedChecklistSettings]
