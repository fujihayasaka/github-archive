export const SelectedTab = {
  User: 'user',
  Team: 'team',
} as const

export type SelectedTab = (typeof SelectedTab)[keyof typeof SelectedTab]

export const defaultSelectedTab = SelectedTab.User

export const IS_KEY = 'is'
