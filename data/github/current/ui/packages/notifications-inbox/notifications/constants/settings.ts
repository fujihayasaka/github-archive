export const NotificationViewPreferenceEnum = {
  DATE: 'sort_by_date',
  GROUP_BY_REPO: 'group_by_repository',
} as const

export type NotificationViewPreferenceEnum =
  (typeof NotificationViewPreferenceEnum)[keyof typeof NotificationViewPreferenceEnum]
