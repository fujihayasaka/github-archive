import type {DiffEntry} from '@github-ui/diff-lines/types'
import {mockDiffSummariesData} from './diff-summaries-mock-data'
import {ProgressiveLoadingStatus, type ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import type {UseQueryResult} from '@github-ui/react-query'
import {useDiffEntry} from '../../page-data/loaders/use-diff-entries'

// Returns 7 diff entries
export const mockDiffEntriesData: DiffEntry[] = mockDiffSummariesData.map(diffSummary => ({
  changeType: diffSummary.changeType,
  collapsed: false,
  commentingEnabled: true,
  diffLines: [],
  diffSize: '1',
  helpUrl: 'help.github.com',
  isBinary: false,
  isTooBig: false,
  linesAdded: diffSummary.linesAdded,
  linesChanged: diffSummary.linesChanged,
  linesDeleted: diffSummary.linesDeleted,
  newCommitOid: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  newTreeEntry: {
    path: diffSummary.path,
    mode: 100644,
    lineCount: 60,
    isGenerated: false,
  },
  objectId: 'some-object-id',
  oldCommitOid: '89c5109b75b889f2842d5692b8f3a260854e591d',
  oldTreeEntry: {
    path: diffSummary.path,
    mode: 100644,
    lineCount: 60,
  },
  path: diffSummary.path,
  pathDigest: diffSummary.pathDigest,
  reviewed: false,
  status: diffSummary.changeType,
  truncatedReason: null,
}))

export function mockProgressiveDiffEntry({path, pathDigest}: {path: string; pathDigest: string}): ProgressiveDiffEntry {
  return {
    path,
    pathDigest,
    loadingStatus: ProgressiveLoadingStatus.Loaded,
    loadSolo: false,
    renderMode: 'RENDER',
  }
}

export function mockUseDiffEntry<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useDiffEntry as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}
