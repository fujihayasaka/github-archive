export const BoolSetting = {
  NotSet: 'not-set',
  Disabled: 'disabled',
  Enabled: 'enabled',
} as const
export type BoolSetting = (typeof BoolSetting)[keyof typeof BoolSetting]
