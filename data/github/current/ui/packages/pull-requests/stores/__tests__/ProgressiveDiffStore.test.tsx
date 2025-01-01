import {renderHook, act, waitFor} from '@testing-library/react'
import {ProgressiveLoadingStatus} from '../../types/progressive-diff-types'
import {setupServer} from 'msw/node'
import {delay, http, HttpResponse} from 'msw'
import {ProgressiveDiffStoreProvider, useProgressiveDiffStore} from '../ProgressiveDiffStore'
import {mockDiffEntriesData} from '../../test-utils/files-changed/diff-entries-mock-data'
import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import type {DiffEntry} from '@github-ui/diff-lines'
import type React from 'react'

// Mock data
const basePath = '/owner/repo/pull/123'
const initialDiffEntries = mockDiffEntriesData

// Mock server setup
const server = setupServer()

// bypass throttle for testing
jest.mock('@github/mini-throttle', () => ({
  ...jest.requireActual('@github/mini-throttle'),
  throttle: jest.fn(fn => {
    return fn
  }),
}))

// Helper function to seed the server with diff entries
const seedServer = ({diffEntries = [], delayTime = 0}: {diffEntries?: DiffEntry[]; delayTime?: number}) => {
  server.use(
    http.get('/:owner/:repo/pull/:number/page_data/diff_entries', async () => {
      // Adding delay option if a test wants to slow down async calls for testing loading states
      await delay(delayTime)
      return HttpResponse.json(diffEntries)
    }),
  )
}

// Helper function to create a wrapper component for the hook
const wrapper = ({children}: {children: React.ReactNode}) => (
  <ProgressiveDiffStoreProvider
    pathName={basePath}
    diffSummaries={mockDiffSummariesData}
    initialDiffEntries={initialDiffEntries.slice(0, 3)}
    selectedPathDigest={undefined}
  >
    {children}
  </ProgressiveDiffStoreProvider>
)

describe('ProgressiveDiffStore', () => {
  beforeEach(() => {
    server.listen()
  })

  afterEach(() => {
    server.resetHandlers()
    jest.clearAllMocks()
  })

  it('initializes with the correct state', () => {
    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {wrapper})

    expect(result.current.diffSummaries).toEqual(mockDiffSummariesData)
    expect(result.current.entries).toHaveLength(mockDiffSummariesData.length)

    // First 3 entries should be loaded initially
    const loadedEntries = result.current.entries.filter(
      entry => entry.loadingStatus === ProgressiveLoadingStatus.Loaded,
    )
    expect(loadedEntries).toHaveLength(3)
  })

  it('loads a selected entry', async () => {
    const selectedFileEntry = mockDiffEntriesData[3]!
    const selectedPathDigest = selectedFileEntry.pathDigest

    seedServer({diffEntries: [selectedFileEntry]})

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper: ({children}) => (
        <ProgressiveDiffStoreProvider
          pathName={basePath}
          diffSummaries={mockDiffSummariesData}
          initialDiffEntries={mockDiffEntriesData.slice(0, 3)}
          selectedPathDigest={selectedPathDigest}
        >
          {children}
        </ProgressiveDiffStoreProvider>
      ),
    })

    // Find the entry to load
    const entryToLoad = result.current.entries.find(entry => entry.pathDigest === selectedPathDigest)
    expect(entryToLoad).toBeDefined()
    expect(entryToLoad?.loadingStatus).not.toBe(ProgressiveLoadingStatus.Loaded)

    // Load the selected entry
    await act(async () => {
      await result.current.loadSelectedEntry(entryToLoad!)
    })

    // Verify entry was loaded
    const loadedEntry = result.current.entries.find(entry => entry.pathDigest === selectedPathDigest)
    expect(loadedEntry).toBeDefined()
    expect(loadedEntry?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
  })

  it('handles loadMore with a selected entry that needs to be loaded first', async () => {
    const selectedFileEntry = mockDiffEntriesData[3]!
    const selectedPathDigest = selectedFileEntry.pathDigest

    seedServer({diffEntries: [selectedFileEntry]})

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper: ({children}) => (
        <ProgressiveDiffStoreProvider
          pathName={basePath}
          diffSummaries={mockDiffSummariesData}
          initialDiffEntries={mockDiffEntriesData.slice(0, 3)}
          selectedPathDigest={selectedPathDigest}
        >
          {children}
        </ProgressiveDiffStoreProvider>
      ),
    })

    // Simulate that an entry has loadSolo flag
    const entryToLoad = result.current.entries.find(entry => entry.pathDigest === selectedPathDigest)
    expect(entryToLoad).toBeDefined()
    expect(entryToLoad?.loadSolo).toBe(true)

    // Call loadMore with a different entry
    const startingAt = result.current.entries[0]!
    await act(async () => {
      await result.current.loadMore(startingAt)
    })

    // Verify the selected entry was loaded instead of the starting entry
    const loadedEntry = result.current.entries.find(entry => entry.pathDigest === selectedPathDigest)
    expect(loadedEntry).toBeDefined()
    expect(loadedEntry?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
  })

  it('processes multiple entries when calling loadEntriesStartingAt', async () => {
    const entriesToLoad = mockDiffEntriesData.slice(3, 6)
    seedServer({diffEntries: entriesToLoad})

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {wrapper})

    // Initial state - only first 3 entries loaded
    const initialLoadedEntries = result.current.entries.filter(
      entry => entry.loadingStatus === ProgressiveLoadingStatus.Loaded,
    )
    expect(initialLoadedEntries).toHaveLength(3)

    // Load more entries starting at index 3
    const startingAt = result.current.entries[3]!
    await act(async () => {
      await result.current.loadEntriesStartingAt(startingAt)
    })

    // Verify multiple entries were loaded
    const loadedEntriesAfter = result.current.entries.filter(
      entry => entry.loadingStatus === ProgressiveLoadingStatus.Loaded,
    )
    expect(loadedEntriesAfter).toHaveLength(6) // 3 initial + 3 loaded
  })

  it('handles the case when no API data is returned', async () => {
    // Set up server to return empty data
    server.use(
      http.get('/:owner/:repo/pull/:number/page_data/diff_entries', () => {
        return HttpResponse.json([])
      }),
    )

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {wrapper})

    // Save initial state
    const initialLoadedCount = result.current.entries.filter(
      e => e.loadingStatus === ProgressiveLoadingStatus.Loaded,
    ).length

    // Try to load more entries
    const startingAt = result.current.entries[3]!
    await act(async () => {
      await result.current.loadEntriesStartingAt(startingAt)
    })

    // Verify state remains unchanged (only original entries are loaded)
    const finalLoadedCount = result.current.entries.filter(
      e => e.loadingStatus === ProgressiveLoadingStatus.Loaded,
    ).length
    expect(finalLoadedCount).toBe(initialLoadedCount)
  })

  it('initializes the store with the correct selected path digest', () => {
    const selectedPathDigest = mockDiffEntriesData[3]!.pathDigest

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper: ({children}) => (
        <ProgressiveDiffStoreProvider
          pathName={basePath}
          diffSummaries={mockDiffSummariesData}
          initialDiffEntries={mockDiffEntriesData.slice(0, 3)}
          selectedPathDigest={selectedPathDigest}
        >
          {children}
        </ProgressiveDiffStoreProvider>
      ),
    })

    // Check basic state initialization
    expect(result.current.diffSummaries).toEqual(mockDiffSummariesData)
    expect(result.current.selectedPathDigest).toBe(selectedPathDigest)

    // Check that the selected entry has loadSolo true
    const selectedEntry = result.current.entries.find(e => e.pathDigest === selectedPathDigest)
    expect(selectedEntry).toBeDefined()
    expect(selectedEntry?.loadSolo).toBe(true)
  })

  it('skips loading when there are no entries to load', async () => {
    jest.mock('../../page-data/loaders/use-diff-entries', () => {
      return {
        loadDiffEntriesForPaths: () => jest.fn,
      }
    })

    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const fetchSpy = jest.spyOn(require('../../page-data/loaders/use-diff-entries'), 'loadDiffEntriesForPaths')

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper: ({children}: React.PropsWithChildren) => (
        <ProgressiveDiffStoreProvider
          pathName={basePath}
          diffSummaries={mockDiffSummariesData.slice(0, 3)}
          initialDiffEntries={initialDiffEntries.slice(0, 3)}
          selectedPathDigest={undefined}
        >
          {children}
        </ProgressiveDiffStoreProvider>
      ),
    })

    // Call loadEntriesStartingAt
    const startingAt = result.current.entries[2]!
    await act(async () => {
      await result.current.loadEntriesStartingAt(startingAt)
    })

    // Verify loadDiffEntriesForPaths was not called
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('throws an error when used outside of a provider', () => {
    // Testing the hook without a provider should throw an error
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

    expect(() => {
      renderHook(() => useProgressiveDiffStore(state => state))
    }).toThrow('Missing ProgressiveDiff.Provider in the tree')

    consoleErrorSpy.mockRestore()
  })

  it('loads more entries when loadMore is called without a selected entry', async () => {
    const entriesToLoad = mockDiffEntriesData.slice(3, 6)
    seedServer({diffEntries: entriesToLoad})

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper,
    })

    // Ensure there's no entry with loadSolo=true
    expect(result.current.entries.some(e => e.loadSolo)).toBe(false)

    // Call loadMore
    const startingAt = result.current.entries[3]!
    await act(async () => {
      await result.current.loadMore(startingAt)
    })

    // Verify entries were loaded
    const loadedEntries = result.current.entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
    expect(loadedEntries.length).toBeGreaterThan(3) // More than initial 3 should be loaded
  })

  it('preserves existing loading states when loading a selected entry and then loading additional diff entries, while async code is running', async () => {
    const selectedPathDigest = mockDiffSummariesData[3]!.pathDigest

    seedServer({
      diffEntries: [mockDiffEntriesData[3]!],
      // Set a delay time on server to handle async loading states
      delayTime: 5,
    })

    const {result} = renderHook(() => useProgressiveDiffStore(state => state), {
      wrapper: ({children}) => (
        <ProgressiveDiffStoreProvider
          pathName={basePath}
          diffSummaries={mockDiffSummariesData}
          initialDiffEntries={mockDiffEntriesData.slice(0, 3)}
          selectedPathDigest={selectedPathDigest}
        >
          {children}
        </ProgressiveDiffStoreProvider>
      ),
    })

    // Verify initial state has zero entries with Loading status
    const initialLoadingEntries = result.current.entries.filter(
      e => e.loadingStatus === ProgressiveLoadingStatus.Loading,
    )
    expect(initialLoadingEntries.length).toBe(0)

    // Load the selected entry
    const selectedEntryToLoad = result.current.entries.find(e => e.pathDigest === selectedPathDigest)!

    // We don't await here as we want to trigger off a 2nd call to the following diff entry after hte selected entry
    act(() => {
      result.current.loadMore(selectedEntryToLoad)
    })

    // Find the selected loading entry in the current stores' entries state.
    const selectedLoadingEntry = result.current.entries.find(e => e.pathDigest === selectedPathDigest)

    // Await for the selectedLoadingEntry to enter into a loading state before async data fetching
    await waitFor(() => expect(selectedLoadingEntry?.loadingStatus).toBe(ProgressiveLoadingStatus.Loading))

    // We don't want to await here again, as we are triggering our second async call.
    act(() => {
      result.current.loadMore(result.current.entries[4]!)
    })

    // Find the selected loading entry in current state.
    const stillLoadingSelectedEntry = result.current.entries.find(e => e.pathDigest === selectedPathDigest)

    // Assert that the selected entry is still loading and that following call for more entries is loading too
    expect(stillLoadingSelectedEntry?.loadingStatus).toBe(ProgressiveLoadingStatus.Loading)
    expect(
      result.current.entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading).length,
    ).toBeGreaterThan(1)
  })
})
