import {useQuery, type QueryKey} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {DiffAnnotation, Thread} from '@github-ui/conversations'
import {useCallback} from 'react'

export function pullRequestMarkersKey(basePath: string): QueryKey {
  return [PageData.markers, basePath]
}

function pullRequestMarkersPayload(basePath: string) {
  const queryKey = pullRequestMarkersKey(basePath)
  return {
    queryKey,
    queryFn: async () => {
      // We're not fetching from an API yet
      // Throwing an error prevents this function from overriding initialData
      throw new Error('This query function should not be executed')
    },
  }
}

export type Markers = {
  threads: {[id: number]: Thread}
  annotations: {[id: number]: DiffAnnotation}
}

/**
 *
 * Returns threads and annotations for the pull request
 */
export function useMarkersData({basePath, initialData}: {basePath: string; initialData?: Markers}) {
  const {queryFn, queryKey} = pullRequestMarkersPayload(basePath)
  return useQuery<Markers | undefined>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
    enabled: false,
  })
}

/**
 * Filters markers data to only include the threads and annotations with the specified IDs
 * @param data The full markers data
 * @param threadIDs The thread IDs to include
 * @param annotationIDs The annotation IDs to include
 * @returns Filtered markers or undefined if no data or all filters return empty
 */
export function filterMarkersData(
  data: Markers | undefined,
  threadIDs: number[],
  annotationIDs: number[],
): {threads: {[id: number]: Thread}; annotations: {[id: number]: DiffAnnotation}} | undefined {
  if (!data) return undefined
  const threads = Object.fromEntries(Object.entries(data.threads).filter(([id]) => threadIDs.includes(parseInt(id))))
  const annotations = Object.fromEntries(
    Object.entries(data.annotations).filter(([id]) => annotationIDs.includes(parseInt(id))),
  )
  if (Object.keys(threads).length === 0 && Object.keys(annotations).length === 0) return undefined
  return {threads, annotations}
}

/**
 *
 * Returns threads and annotations aka "markers" for the pull request based on specific thread IDs
 * We use `select` to minimize the number of re-renders
 */
export function useMarkersDataWithSelectThreadAndAnnotationIDs({
  basePath,
  threadAndAnnotationIDs,
}: {
  basePath: string
  threadAndAnnotationIDs: {threadIDs: number[]; annotationIDs: number[]}
}) {
  const {threadIDs, annotationIDs} = threadAndAnnotationIDs
  const {queryFn, queryKey} = pullRequestMarkersPayload(basePath)
  return useQuery({
    queryKey,
    queryFn,
    staleTime: Infinity,
    select: useCallback(
      (data: Markers | undefined) => filterMarkersData(data, threadIDs, annotationIDs),
      [annotationIDs, threadIDs],
    ),
  })
}

export function countComments(data: Markers | undefined, threadIDs?: number[]): number {
  if (!data) return 0
  const threads = threadIDs
    ? Object.values(data.threads).filter(thread => threadIDs.includes(parseInt(thread.id)))
    : Object.values(data.threads)
  return threads.reduce(
    (acc, thread) => (thread.isResolved || thread.isOutdated ? acc : acc + thread.commentsData.comments.length),
    0,
  )
}

/**
 * Returns the count of comments for the pull request based on specific thread IDs or all threads if no ids are provided
 */
export function useCommentCountFromMarkersData({basePath, threadIDs}: {basePath: string; threadIDs?: number[]}) {
  const {queryFn, queryKey} = pullRequestMarkersPayload(basePath)
  return useQuery({
    queryKey,
    queryFn,
    staleTime: Infinity,
    select: useCallback((data: Markers | undefined) => countComments(data, threadIDs), [threadIDs]),
  })
}
