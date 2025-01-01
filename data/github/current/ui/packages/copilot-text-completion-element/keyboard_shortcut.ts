// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
export const KeyboardShortcut = {
  accept: 'Tab',
  accessibleInspect: 'Mod+i',
  mod: 'Mod',
} as const

export type KeyboardShortcut = (typeof KeyboardShortcut)[keyof typeof KeyboardShortcut]
