export const CommentsPreference = {
  Visible: 'visible',
  Collapsed: 'collapsed',
} as const

export const DiffLineSpacingPreference = {
  Compact: 'compact',
  Relaxed: 'relaxed',
} as const

export const SplitPreference = {
  Split: 'split',
  Unified: 'unified',
} as const

export type CommentsPreference = (typeof CommentsPreference)[keyof typeof CommentsPreference]
export type DiffLineSpacingPreference = (typeof DiffLineSpacingPreference)[keyof typeof DiffLineSpacingPreference]
export type SplitPreference = (typeof SplitPreference)[keyof typeof SplitPreference]

export type DiffViewSettings = {
  commentsPreference: CommentsPreference
  hideWhitespace: boolean
  splitPreference: SplitPreference
  lineSpacing: DiffLineSpacingPreference
}

export type CommitNotices = 'compact_diff_lines'

export type UserNotice<T> = {
  name: T
  dismissed: boolean
}
