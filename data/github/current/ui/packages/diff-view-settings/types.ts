export const CommentsPreference = {
  Visible: 'visible',
  Collapsed: 'collapsed',
} as const

export type CommentsPreference = (typeof CommentsPreference)[keyof typeof CommentsPreference]
export type DiffLineSpacing = 'compact' | 'relaxed'
export type SplitPreference = 'split' | 'unified'

export type DiffViewSettings = {
  commentsPreference: CommentsPreference
  hideWhitespace: boolean
  splitPreference: SplitPreference
  lineSpacing: DiffLineSpacing
}

export type CommitNotices = 'compact_diff_lines'

export type UserNotice<T> = {
  name: T
  dismissed: boolean
}
