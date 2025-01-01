export type LanguageTocItem = {
  name: string
  key: string
  active: boolean
}

export type ModelToc = {
  [language: string]: LanguageTocItem
}

export const Feedback = {
  UNKNOWN: 0,
  POSITIVE: 1,
  NEGATIVE: 2,
} as const

export type Feedback = (typeof Feedback)[keyof typeof Feedback]

export type NegativeFeedbackReason = 'harmful' | 'untrue' | 'unhelpful' | 'other'

export type FeedbackState = {
  satisfaction: Feedback
  reasons: NegativeFeedbackReason[]
  feedbackText: string
  contactConsent: boolean
  model: string
}
