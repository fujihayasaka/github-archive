export type DiffLineSpacing = 'compact' | 'relaxed'
export type SplitPreference = 'split' | 'unified'

export type DiffViewSettings = {
  hideWhitespace: boolean
  splitPreference: SplitPreference
  lineSpacing: DiffLineSpacing
}

export type CommitNotices = 'compact_diff_lines'

export type UserNotice<T> = {
  name: T
  dismissed: boolean
}
