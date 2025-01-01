export type FeedbackOptions = Array<{label: string; value: string}>

export type FeedbackSubmitHandler = (
  type: 'POSITIVE' | 'NEGATIVE',
  feedbackChoice?: string[],
  textResponse?: string,
) => void
