export const PlaygroundContentOption = {
  CHAT: 0,
  CODE: 1,
  JSON: 2,
  PARAMETERS: 3,
} as const

export type PlaygroundContentOption = (typeof PlaygroundContentOption)[keyof typeof PlaygroundContentOption]

export const playgroundContentSuffixes = {
  [PlaygroundContentOption.CHAT]: '',
  [PlaygroundContentOption.CODE]: '/code',
  [PlaygroundContentOption.JSON]: '/json',
}

export type Labels = {
  task: string
  tags: string[]
}
