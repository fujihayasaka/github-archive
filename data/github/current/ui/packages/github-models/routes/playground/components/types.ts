export enum PlaygroundContentOption {
  CHAT = 0,
  CODE = 1,
  JSON = 2,
}

export const playgroundContentSuffixes = {
  [PlaygroundContentOption.CHAT]: '',
  [PlaygroundContentOption.CODE]: '/code',
  [PlaygroundContentOption.JSON]: '/json',
}

export type Labels = {
  task: string
  tags: string[]
}
