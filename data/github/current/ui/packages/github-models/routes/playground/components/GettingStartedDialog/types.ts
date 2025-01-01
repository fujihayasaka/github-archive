export type LanguageTocItem = {
  name: string
  key: string
  active: boolean
}

export type ModelToc = {
  [language: string]: Language
}

export enum Feedback {
  UNKNOWN = 0,
  POSITIVE = 1,
  NEGATIVE = 2,
}

export type NegativeFeedbackReason = 'harmful' | 'untrue' | 'unhelpful' | 'other'

export type FeedbackState = {
  satisfaction: Feedback
  reasons: NegativeFeedbackReason[]
  feedbackText: string
  contactConsent: boolean
  model: string
}
