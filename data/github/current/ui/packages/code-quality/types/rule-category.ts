export const RuleCategory = {
  Reliability: 'reliability',
  Maintainability: 'maintainability',
} as const

export type RuleCategory = (typeof RuleCategory)[keyof typeof RuleCategory]
