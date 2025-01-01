export const ReadOnlyState = {
  Editable: 0,
  Readonly: 1,
  ReadonlyWithPublicIPRunner: 2,
} as const
export type ReadOnlyState = (typeof ReadOnlyState)[keyof typeof ReadOnlyState]
