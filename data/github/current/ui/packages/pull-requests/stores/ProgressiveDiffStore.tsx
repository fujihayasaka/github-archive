import {createStore, useStore} from 'zustand'
import {devtools} from 'zustand/middleware'
import {ProgressiveLoadingStatus, type ProgressiveDiffEntry} from '../types/progressive-diff-types'
import {buildProgressiveDiffEntries} from '../utils/build-progressive-diff-entries'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import type {DiffEntry} from '@github-ui/diff-lines'
import {createContext, useContext, useRef} from 'react'
import {loadDiffEntriesForPaths} from '../page-data/loaders/use-diff-entries'
import {identifyDiffEntriesToLoad} from '../utils/identify-diff-entries-to-load'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {throttle} from '@github/mini-throttle'

interface ProgressiveDiffStoreInitOpts {
  diffSummaries: PullRequestFileTreeDiff[]
  initialDiffEntries: DiffEntry[]
  selectedPathDigest: string | undefined
  pathName: string
  prxFilesLiteThrottle?: boolean | undefined
  prxFilesMediumThrottle?: boolean | undefined
}

export interface ProgressiveDiffState {
  // State
  diffSummaries: PullRequestFileTreeDiff[]
  entries: ProgressiveDiffEntry[]
  loadedPathDigests: Set<string>
  loadingPathDigests: Set<string>
  selectedPathDigest: string | undefined
  // Actions
  loadMore: (startingAt: ProgressiveDiffEntry) => Promise<void>
  loadSelectedEntry: (selectedEntry: ProgressiveDiffEntry) => Promise<void>
  loadEntriesStartingAt: (startingAt: ProgressiveDiffEntry) => Promise<void>
}

type ProgressiveDiffStore = ReturnType<typeof createProgressiveDiffStore>

const createProgressiveDiffStore = ({
  diffSummaries,
  initialDiffEntries,
  selectedPathDigest,
  pathName,
  prxFilesLiteThrottle,
  prxFilesMediumThrottle,
}: ProgressiveDiffStoreInitOpts) => {
  const initialLoadedPathDigests = initialDiffEntries.map(entry => entry.pathDigest)
  const loadedPathDigests = new Set(initialLoadedPathDigests)
  let throttleTime: number

  if (prxFilesMediumThrottle) {
    throttleTime = 100
  } else if (prxFilesLiteThrottle) {
    throttleTime = 50
  } else {
    throttleTime = 0
  }

  // Set initial progressive diff entries "state"
  const entries = buildProgressiveDiffEntries({
    diffSummaries,
    loadedPathDigests,
    loadingPathDigests: new Set<string>(),
    selectedPathDigest,
  })

  const store = createStore<ProgressiveDiffState>()(
    devtools((set, get) => ({
      diffSummaries,
      entries,
      selectedPathDigest,
      loadSelectedEntry: async (selectedEntry: ProgressiveDiffEntry) => {
        const previouslyLoadedPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
          .map(e => e.pathDigest)
        const previouslyLoadingPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading)
          .map(e => e.pathDigest)

        set(
          state => ({
            entries: buildProgressiveDiffEntries({
              diffSummaries: state.diffSummaries,
              loadedPathDigests: new Set(previouslyLoadedPathDigests),
              loadingPathDigests: new Set([...previouslyLoadingPathDigests, selectedEntry.pathDigest]),
              selectedPathDigest: state.selectedPathDigest,
            }),
          }),
          undefined,
          'loadSelectedEntry#preFetch',
        )

        // Fetch more diff entries
        const newlyLoadedDiffEntries = await loadDiffEntriesForPaths(pathName, {
          paths: [selectedEntry.path],
        })

        const newEntry = newlyLoadedDiffEntries?.[0]

        if (!newEntry) {
          // We are not handling retry logic currently
          return
        }

        const currentLoadedPathDigests = [
          ...get()
            .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
            .map(e => e.pathDigest),
          newEntry.pathDigest,
        ]
        const currentLoadingPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading)
          .filter(e => e.pathDigest !== newEntry.pathDigest)
          .map(e => e.pathDigest)

        const updatedEntries = buildProgressiveDiffEntries({
          diffSummaries: get().diffSummaries,
          loadedPathDigests: new Set(currentLoadedPathDigests),
          loadingPathDigests: new Set(currentLoadingPathDigests),
          selectedPathDigest: get().selectedPathDigest,
        })

        return set(
          {
            entries: updatedEntries,
          },
          undefined,
          'loadSelectedEntry#postFetch',
        )
      },
      loadEntriesStartingAt: throttle(async (startingAt: ProgressiveDiffEntry) => {
        let pathsToFetch: string[] = []
        let pathDigestsToFetch: string[] = []
        const previouslyLoadedPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
          .map(e => e.pathDigest)
        const previouslyLoadingPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading)
          .map(e => e.pathDigest)

        const {pathsToLoad, pathDigestsToLoad} = identifyDiffEntriesToLoad({
          progressiveDiffEntries: get().entries,
          startingAt,
        })

        if (pathsToLoad.size === 0) return

        pathsToFetch = Array.from(pathsToLoad)
        pathDigestsToFetch = Array.from(pathDigestsToLoad)

        set(
          state => ({
            entries: buildProgressiveDiffEntries({
              diffSummaries: state.diffSummaries,
              loadedPathDigests: new Set(previouslyLoadedPathDigests),
              loadingPathDigests: new Set([...previouslyLoadingPathDigests, ...pathDigestsToFetch]),
              selectedPathDigest: state.selectedPathDigest,
            }),
          }),
          undefined,
          'loadEntriesStartingAt#preFetch',
        )

        const newlyLoadedDiffEntries = await loadDiffEntriesForPaths(pathName, {
          paths: pathsToFetch,
        })

        const noApiData = !newlyLoadedDiffEntries || newlyLoadedDiffEntries.length === 0
        if (noApiData) {
          const currentLoadedPathDigests = [
            ...get()
              .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
              .map(e => e.pathDigest),
          ]
          const currentLoadingPathDigests = get()
            .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading)
            .map(e => e.pathDigest)

          return set(
            {
              entries: buildProgressiveDiffEntries({
                diffSummaries: get().diffSummaries,
                loadedPathDigests: new Set(currentLoadedPathDigests),
                loadingPathDigests: new Set(currentLoadingPathDigests),
                selectedPathDigest: get().selectedPathDigest,
              }),
            },
            undefined,
            'loadEntriesStartingAt#postFetch#noAPIData',
          )
        }

        const currentLoadedPathDigests = [
          ...get()
            .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loaded)
            .map(e => e.pathDigest),
          ...newlyLoadedDiffEntries.map(e => e.pathDigest),
        ]
        const currentLoadingPathDigests = get()
          .entries.filter(e => e.loadingStatus === ProgressiveLoadingStatus.Loading)
          .filter(e => !newlyLoadedDiffEntries.map(ne => ne.pathDigest).includes(e.pathDigest))
          .map(e => e.pathDigest)

        set(
          (state: ProgressiveDiffState) => ({
            ...state,
            entries: buildProgressiveDiffEntries({
              diffSummaries: get().diffSummaries,
              loadedPathDigests: new Set(currentLoadedPathDigests),
              loadingPathDigests: new Set(currentLoadingPathDigests),
              selectedPathDigest: get().selectedPathDigest,
            }),
          }),
          undefined,
          'loadEntriesStartingAt#postFetch',
        )
      }, throttleTime),
      loadMore: async (startingAt: ProgressiveDiffEntry) => {
        const selectedEntryToLoadFirst = get().entries.find(
          e => e.loadSolo && e.loadingStatus === ProgressiveLoadingStatus.NotLoaded,
        )

        if (selectedEntryToLoadFirst) {
          return get().loadSelectedEntry(selectedEntryToLoadFirst)
        } else {
          return get().loadEntriesStartingAt(startingAt)
        }
      },
    })),
  )

  return store
}

const ProgressiveDiffStoreContext = createContext<ProgressiveDiffStore | null>(null)

export function useProgressiveDiffStore<T>(selector: (state: ProgressiveDiffState) => T): T {
  const store = useContext(ProgressiveDiffStoreContext)
  if (!store) throw new Error('Missing ProgressiveDiff.Provider in the tree')
  return useStore(store, selector)
}

export function ProgressiveDiffStoreProvider({
  children,
  diffSummaries,
  initialDiffEntries,
  selectedPathDigest,
  pathName,
}: React.PropsWithChildren<ProgressiveDiffStoreInitOpts>) {
  const storeRef = useRef<ProgressiveDiffStore | null>(null)
  const prxFilesLiteThrottle = useFeatureFlag('prx_files_lite_throttle')
  const prxFilesMediumThrottle = useFeatureFlag('prx_files_medium_throttle')

  if (!storeRef.current) {
    storeRef.current = createProgressiveDiffStore({
      diffSummaries,
      initialDiffEntries,
      selectedPathDigest,
      pathName,
      prxFilesLiteThrottle,
      prxFilesMediumThrottle,
    })
  }

  return (
    <ProgressiveDiffStoreContext.Provider value={storeRef.current}>{children}</ProgressiveDiffStoreContext.Provider>
  )
}
