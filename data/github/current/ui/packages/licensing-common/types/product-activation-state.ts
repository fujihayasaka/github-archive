export const ProductActivationState = {
  Active: 'active',
  Inactive: 'inactive',
  Trial: 'trial',
  TrialExpired: 'trial_expired',
} as const

export type ProductActivationState = (typeof ProductActivationState)[keyof typeof ProductActivationState]
