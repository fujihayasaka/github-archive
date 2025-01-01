export const PlaygroundContentOption = {
  CHAT: 0,
  CODE: 1,
  JSON: 2,
} as const

export type PlaygroundContentOption = (typeof PlaygroundContentOption)[keyof typeof PlaygroundContentOption]

export const playgroundContentSuffixes = {
  [PlaygroundContentOption.CHAT]: '',
  [PlaygroundContentOption.CODE]: '/code',
  [PlaygroundContentOption.JSON]: '/json',
}

export const PlaygroundViewOption = {
  PROMPT: 0,
  EVALS: 1,
} as const

export type PlaygroundViewOption = (typeof PlaygroundViewOption)[keyof typeof PlaygroundViewOption]

export const playgroundViewSuffixes = {
  [PlaygroundViewOption.PROMPT]: '/prompt',
  [PlaygroundViewOption.EVALS]: '/evals',
}

export type Labels = {
  task: string
  tags: string[]
}
