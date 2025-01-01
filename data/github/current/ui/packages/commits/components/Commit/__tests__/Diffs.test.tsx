import {
  defaultViewSettings,
  useDiffViewSettingsData,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {noop} from '@github-ui/noop'
import {commitContextLinesPath} from '@github-ui/paths'
import {screen} from '@testing-library/react'

import {
  mockDiffLinesResponse,
  payloadWithBinaryDiff,
  payloadWithDiffs,
  payloadWithRichDependencyDiff,
  payloadWithRichDiff,
  payloadWithRichDiffNotLoaded,
  payloadWithRichRenderedDiff,
  payloadWithTooBigDiffs,
  payloadWithZeroChangedLinesDiff,
} from '../../../test-utils/commit-mock-data'
import {renderCommit} from '../../../test-utils/Render'
import type {CommitPayload, DiffEntryDataWithExtraInfo} from '../../../types/commit-types'
import {Diffs} from '../Diffs'

jest.mock('@github-ui/diff-view-settings/page-data/payloads/diff-view-settings', () => ({
  ...jest.requireActual('@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'),
  useDiffViewSettingsData: jest.fn(),
}))
const mockedUseAppPayload = jest.mocked(useDiffViewSettingsData)

beforeEach(() => {
  jest.clearAllMocks()
  // jests querySelector doesn't like focus-within so we have to mock it
  jest.spyOn(document, 'querySelector').mockImplementation(() => {
    return null
  })
  mockedUseAppPayload.mockReturnValue({
    data: {...defaultViewSettings, splitPreference: 'split'},
    error: null,
    isError: false,
    isLoading: false,
    status: 'success',
    isLoadingError: false,
    isPending: false,
    isFetched: true,
    isSuccess: true,
    isRefetchError: false,
    dataUpdatedAt: 0,
    errorUpdatedAt: 0,
    failureCount: 0,
    isStale: false,
    failureReason: null,
    isFetching: false,
    isFetchedAfterMount: true,
    isPaused: false,
    isInitialLoading: false,
    errorUpdateCount: 0,
    fetchStatus: 'idle',
    isRefetching: false,
    refetch: jest.fn(),
    isPlaceholderData: false,
    promise: Promise.resolve(defaultViewSettings),
  })
})

function renderDiffs(payload: CommitPayload, unselectedFileExtensions: Set<string>, filterTerm = '') {
  return renderCommit(
    <Diffs
      totalFileCount={0}
      headerInfo={payload.headerInfo}
      treeToggleElement={<div>treeToggleElement</div>}
      isTreeExpanded={false}
      searchTerm={''}
      filterTerm={filterTerm}
      setSearchTerm={noop}
      ignoreWhitespace={payload.ignoreWhitespace}
      diffEntryData={payload.diffEntryData as DiffEntryDataWithExtraInfo[]}
      contextLinePathURL={commitContextLinesPath({
        owner: payload.repo.ownerLogin,
        repo: payload.repo.name,
        commitish: payload.commit.oid,
      })}
      unselectedFileExtensions={unselectedFileExtensions}
      repo={payload.repo}
      oid={payload.commit.oid}
    />,
    payload,
  )
}
function addLRMMarkToString(str: string) {
  return `\u200E${str}`
}

test('renders diff files', () => {
  renderDiffs(payloadWithDiffs, new Set())

  expect(screen.getByText(addLRMMarkToString('src/index.js'))).toBeInTheDocument()
  expect(screen.getByText(addLRMMarkToString('1234.json'))).toBeInTheDocument()
  expect(screen.getByText(addLRMMarkToString('src/components/Component.ts'))).toBeInTheDocument()
  expect(screen.getByText(addLRMMarkToString('src/components/Component.test.js'))).toBeInTheDocument()
  // An icon appears bewteen the old and new name for renamed files
  expect(screen.getByText(addLRMMarkToString('src/components/Component.css.old'), {exact: false})).toBeInTheDocument()
})

test('shows old and new content for modified files for split view', () => {
  renderDiffs(payloadWithDiffs, new Set())

  // Context lines will appear twice for each side in split view
  expect(screen.getAllByText('text2')).toHaveLength(2)
  expect(screen.getByText('text3')).toBeInTheDocument()
  expect(screen.getByText('text4')).toBeInTheDocument()
  // Context lines will appear twice for each side in split view
  expect(screen.getAllByText('text5')).toHaveLength(2)
})

test('shows old and new content for modified files for unified view', () => {
  mockedUseAppPayload.mockReturnValue({
    data: {...defaultViewSettings, splitPreference: 'unified'},
    error: null,
    isError: false,
    isLoading: false,
    status: 'success',
    isLoadingError: false,
    isPending: false,
    isFetched: true,
    isSuccess: true,
    isRefetchError: false,
    dataUpdatedAt: 0,
    errorUpdatedAt: 0,
    failureCount: 0,
    isStale: false,
    failureReason: null,
    isFetching: false,
    isFetchedAfterMount: true,
    isPaused: false,
    isInitialLoading: false,
    errorUpdateCount: 0,
    fetchStatus: 'idle',
    isRefetching: false,
    refetch: jest.fn(),
    isPlaceholderData: false,
    promise: Promise.resolve(defaultViewSettings),
  })
  renderDiffs({...payloadWithDiffs}, new Set())

  // Context lines will appear once the in unified view
  expect(screen.getByText('text2')).toBeInTheDocument()
  expect(screen.getByText('text3')).toBeInTheDocument()
  expect(screen.getByText('text4')).toBeInTheDocument()
  expect(screen.getByText('text5')).toBeInTheDocument()
})

test('shows only new content for added files', () => {
  renderDiffs(payloadWithDiffs, new Set())

  expect(screen.getByText('text1')).toBeInTheDocument()
})

test('renamed only files show that they have been renamed without changes', () => {
  renderDiffs(payloadWithDiffs, new Set())

  expect(screen.getByText('File renamed without changes.')).toBeInTheDocument()
})

test('does not show content of deleted files by default', async () => {
  const sha1 = (payloadWithDiffs.diffEntryData[2] as DiffEntryDataWithExtraInfo).oldOid
  const sha2 = (payloadWithDiffs.diffEntryData[2] as DiffEntryDataWithExtraInfo).newOid
  const diffNumber = (payloadWithDiffs.diffEntryData[2] as DiffEntryDataWithExtraInfo).diffNumber
  const route = `/monalisa/smile/diffs/${diffNumber}/diff-lines?sha1=${sha1}&sha2=${sha2}`
  mockFetch.mockRouteOnce(route, mockDiffLinesResponse)

  const {user} = renderDiffs(payloadWithDiffs, new Set())

  expect(screen.getByText('This file was deleted.')).toBeInTheDocument()
  expect(screen.queryByText('deferred text')).not.toBeInTheDocument()

  const loadDiffButton = screen.getByText('Load Diff')
  expect(loadDiffButton).toBeInTheDocument()
  await user.click(loadDiffButton)

  expectMockFetchCalledTimes(route, 1)

  expect(await screen.findByText('deferred text')).toBeInTheDocument()
})

test('does not show diff entries that are too big by default', async () => {
  const sha1 = (payloadWithTooBigDiffs.diffEntryData[0] as DiffEntryDataWithExtraInfo).oldOid
  const sha2 = (payloadWithTooBigDiffs.diffEntryData[0] as DiffEntryDataWithExtraInfo).newOid
  const diffNumber = (payloadWithTooBigDiffs.diffEntryData[0] as DiffEntryDataWithExtraInfo).diffNumber
  const route = `/monalisa/smile/diffs/${diffNumber}/diff-lines?sha1=${sha1}&sha2=${sha2}`
  mockFetch.mockRouteOnce(route, mockDiffLinesResponse)

  const {user} = renderDiffs(payloadWithTooBigDiffs, new Set())

  expect(screen.getByText('Large diffs are not rendered by default.')).toBeInTheDocument()
  expect(screen.queryByText('deferred text')).not.toBeInTheDocument()

  // can load diff lines for a file that is too big
  const loadDiffButton = screen.getByText('Load Diff')
  expect(loadDiffButton).toBeInTheDocument()
  await user.click(loadDiffButton)

  expectMockFetchCalledTimes(route, 1)

  expect(await screen.findByText('deferred text')).toBeInTheDocument()
})

test('does not show files if their extensions are unselected', () => {
  renderDiffs(payloadWithDiffs, new Set(['.js']))

  expect(screen.getByText(addLRMMarkToString('src/components/Component.ts'))).toBeInTheDocument()
  expect(screen.queryByText(addLRMMarkToString('src/components/Component.test.js'))).not.toBeInTheDocument()
})

test('filters diffs by paths that include the filter term', () => {
  renderDiffs(payloadWithDiffs, new Set(), 'test')

  expect(screen.getByText(addLRMMarkToString('src/components/Component.test.js'))).toBeInTheDocument()
  expect(screen.queryByText(addLRMMarkToString('src/index.js'))).not.toBeInTheDocument()
  expect(screen.queryByText(addLRMMarkToString('src/components/Component.ts'))).not.toBeInTheDocument()
  expect(
    screen.queryByText(addLRMMarkToString('src/components/Component.css.old'), {exact: false}),
  ).not.toBeInTheDocument()
})

test('renders prose diffs', () => {
  renderDiffs(payloadWithRichDiff, new Set())

  expect(screen.getByText('proseDiffHtml')).toBeInTheDocument()
})

test('renders prose data async', async () => {
  mockFetch.mockRouteOnce('/monalisa/smile/commit/052a205c10a5a949ec8b00521da6508e7f2eab1fc/rich_diff/src%2Findex.js', {
    proseDiffHtml: 'proseDiffHtml',
  })
  renderDiffs(payloadWithRichDiffNotLoaded, new Set())

  expectMockFetchCalledTimes(
    '/monalisa/smile/commit/052a205c10a5a949ec8b00521da6508e7f2eab1fc/rich_diff/src%2Findex.js',
    1,
  )

  expect(await screen.findByText('proseDiffHtml', undefined, {timeout: 1000})).toBeInTheDocument()
})

test('renders rendered rich diff', () => {
  renderDiffs(payloadWithRichRenderedDiff, new Set())

  expect(screen.getByTitle('File display')).toBeInTheDocument()
})

test('renders rendered rich diff async', async () => {
  mockFetch.mockRouteOnce('/monalisa/smile/commit/052a205c10a5a949ec8b00521da6508e7f2eab1fc/rich_diff/src%2Findex.js', {
    fileRendererInfo: {
      identityUuid: 'identityUuid',
      type: 'renderType',
      size: 1,
      url: 'displayUrl',
    },
  })
  renderDiffs(payloadWithRichDiffNotLoaded, new Set())

  expectMockFetchCalledTimes(
    '/monalisa/smile/commit/052a205c10a5a949ec8b00521da6508e7f2eab1fc/rich_diff/src%2Findex.js',
    1,
  )

  expect(await screen.findByTitle('File display', undefined, {timeout: 1000})).toBeInTheDocument()
})

test('renders dependency diff', () => {
  renderDiffs(payloadWithRichDependencyDiff, new Set())

  expect(screen.getByText('Loading Dependency Review...')).toBeInTheDocument()
})

test('renders the expand/collapse button if the file is not binary and has a changed line', async () => {
  renderDiffs(payloadWithDiffs, new Set())

  expect(await screen.findByLabelText('expand all lines: src/index.js')).toBeInTheDocument()
})

test('does not render the expand/collapse button if the file is binary', () => {
  renderDiffs(payloadWithBinaryDiff, new Set())

  expect(screen.queryByLabelText('expand all lines')).not.toBeInTheDocument()
})
test('does not render the expand/collapse button if the file has 0 changed lines', () => {
  renderDiffs(payloadWithZeroChangedLinesDiff, new Set())

  expect(screen.queryByLabelText('expand all lines')).not.toBeInTheDocument()
})
