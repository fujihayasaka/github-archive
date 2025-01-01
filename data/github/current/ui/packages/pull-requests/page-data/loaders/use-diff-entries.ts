import type {DiffEntry} from '@github-ui/diff-lines/types'
import {
  parseJSONWithBetterErrors,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useQuery, type QueryKey} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {produce} from 'immer'
import {useCallback} from 'react'
import {getQueryClient} from '@github-ui/react-core/query-client'

function diffEntriesKey(basePath: string): QueryKey {
  return [PageData.diffEntries, basePath]
}

function diffEntriesOptions(basePath: string) {
  return {
    queryKey: diffEntriesKey(basePath),
    queryFn: async () => {
      return []
    },
  }
}

export function useDiffEntries(basePath: string, initialData?: DiffEntry[]) {
  const queryKey = diffEntriesKey(basePath)

  return useQuery<DiffEntry[]>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : []
    },
    initialData,
    staleTime: Infinity,
  })
}

/**
 * Returns a single diff entry for the given path digest
 */
export function useDiffEntry(basePath: string, pathDigest: string) {
  const {queryKey, queryFn} = diffEntriesOptions(basePath)

  return useQuery({
    queryKey,
    queryFn,
    select: useCallback(
      (data: DiffEntry[] | []) => {
        if (!data) return undefined
        return data.find(entry => entry.pathDigest === pathDigest)
      },
      [pathDigest],
    ),
    staleTime: Infinity,
  })
}

export async function loadDiffEntriesForPaths(basePath: string, variables: {paths: string[]; signal?: AbortSignal}) {
  const queryClient = getQueryClient()
  const queryKey = diffEntriesKey(basePath)

  const newDiffEntries = await fetchDiffEntries(basePath, variables.paths, variables.signal)

  if (newDiffEntries && newDiffEntries.length > 0) {
    queryClient.setQueryData(
      queryKey,
      produce((oldDiffEntriesData: DiffEntry[]) => {
        if (!oldDiffEntriesData) return newDiffEntries

        // Merge old and new without dupes
        for (const newEntry of newDiffEntries) {
          if (oldDiffEntriesData.find(oldEntry => oldEntry.pathDigest === newEntry.pathDigest)) {
            continue
          }
          oldDiffEntriesData.push(newEntry)
        }
      }),
    )
  }
  return newDiffEntries
}

/**
 * Fetches diff entries for given paths
 */
async function fetchDiffEntries(
  basePath: string,
  paths: string[],
  signal?: AbortSignal,
): Promise<DiffEntry[] | undefined> {
  const params = new URLSearchParams()
  params.append('paths', paths.join(','))
  const fetchUrl = `${basePath}/page_data/${PageData.diffEntries}?paths=${paths}`

  try {
    const response = await reactFetchJSON(fetchUrl, {signal})
    if (signal?.aborted) return undefined
    const data = await parseJSONWithBetterErrors(response)
    throwErrorsIfBadResponse(response, data)
    return data ?? undefined
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      return
    } else {
      throw error
    }
  }
}
