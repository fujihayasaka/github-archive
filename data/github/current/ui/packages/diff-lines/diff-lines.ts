export {Diff, DiffErrorFallback, type DiffProps} from './components/Diff'
export {DiffLines} from './components/DiffLines'
export {DiffFind} from './components/DiffFind'
export type {DiffFindRequest, FocusedSearchResult} from './hooks/use-diff-search-results'
export type {DiffLinesProps} from './components/DiffLines'
export {HunkKebabIcon} from './components/DiffLineTableCellParts'
export {RichDiff} from './components/RichDiff'
export {SubmoduleDiff} from './components/SubmoduleDiff'
export {getLineBackgroundColor} from './helpers/line-helpers'

export type {
  Comment,
  Comments,
  DiffEntry,
  DiffEntryData,
  DiffLine,
  Thread,
  ThreadsData,
  LineRange,
  FileDiffReference,
} from './types'

export {SelectedDiffRowRangeContextProvider} from './contexts/SelectedDiffRowRangeContext'
export {useDiffFindOpen, DiffFindOpenProvider} from './contexts/DiffFindOpenContext'
export {parseAnnotationHash, parseCommentHash} from './helpers/document-hash-helpers'
export {useDiffSearchResults} from './hooks/use-diff-search-results'
export type {DiffMatchContent} from './helpers/find-in-diff'
export {findInDiffWorkerJob} from './helpers/find-in-diff'
