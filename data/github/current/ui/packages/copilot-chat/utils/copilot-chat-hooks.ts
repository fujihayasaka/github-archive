import {verifiedFetch} from '@github-ui/verified-fetch'
import {useMutation, useQueries, useQuery, useQueryClient} from '@tanstack/react-query'
import {useCallback, useEffect, useRef, useState} from 'react'

import {copilotLocalStorage} from './copilot-local-storage'
import {useChatPanelReferenceContext, useChatState} from './CopilotChatContext'
import {useChatManager} from './CopilotChatManagerContext'

export interface IndexingState {
  code: TopicIndexStatus
  docs: TopicIndexStatus
  requestStatus: CanIndexStatus
  remainingRepoIndexTokens?: number
}

interface IndexingStateResponse {
  code_status: TopicIndexStatus
  docs_status: TopicIndexStatus
  can_index: CanIndexStatus
  remaining_repo_index_tokens?: number
}

export enum TopicIndexStatus {
  Unindexed = 'not_indexed',
  Indexed = 'indexed',
  Indexing = 'indexing',
  PartiallyIndexed = 'partially_indexed',
  Unknown = 'unknown',
}

export enum CanIndexStatus {
  Requested = 'requested', // requested is used in TopicIndexState.tsx, but it does not look like it is something that is ever returned
  NotFound = 'not_found',
  Unauthorized = 'unauthorized',
  ServiceUnavailable = 'service_unavailable',
  QuotaExhausted = 'quota_exhausted',
  Forbidden = 'forbidden',
  CanIndex = 'ok',
  IndexingError = 'indexing_error',
  RequestFailed = 'request_failed',
  Unknown = 'unknown',
}

const errorStatuses = [
  CanIndexStatus.NotFound,
  CanIndexStatus.Unauthorized,
  CanIndexStatus.ServiceUnavailable,
  CanIndexStatus.QuotaExhausted,
  CanIndexStatus.Forbidden,
  CanIndexStatus.RequestFailed,
]

interface FilterWorkerResponse {
  query: string
  list: string[]
}

export const MIN_PANEL_HEIGHT = 256
export const MIN_PANEL_WIDTH = 400

export function useFilter(
  list: string[] | null,
  query: string,
  workerPath: string | undefined,
): [string[], boolean, () => void] {
  const workerRef = useRef<Worker>()
  const lastQueryRef = useRef<string>()
  const lastMatchesRef = useRef<string[]>([])
  const isWorkerWorking = useRef<boolean>(false)
  const [matches, setMatches] = useState<string[]>([])
  const [searching, setSearching] = useState<boolean>(true)

  const clearMatches = useCallback(() => {
    setMatches([])
    setSearching(false)
  }, [])

  const createWorker = useCallback(() => {
    if (!workerPath || !list) return

    try {
      const worker = new Worker(workerPath)
      worker.onmessage = ({data}: {data: FilterWorkerResponse}) => {
        isWorkerWorking.current = false
        setMatches(data.list)
        setSearching(false)
        lastQueryRef.current = data.query
        lastMatchesRef.current = data.list
      }

      workerRef.current = worker
    } catch (e) {
      // TODO: handle when worker cannot be created
      // eslint-disable-next-line no-console
      console.warn('Web workers are not available: ', e)
    }
  }, [workerPath, list])

  const postWorkerMessage = useCallback(
    (newQuery: string) => {
      if (isWorkerWorking.current) {
        workerRef.current?.terminate()
        createWorker()
      }

      const usePreviousMatches =
        lastQueryRef.current && newQuery.startsWith(lastQueryRef.current) && lastMatchesRef.current.length

      setSearching(true)
      isWorkerWorking.current = true
      workerRef.current?.postMessage({baseList: usePreviousMatches ? lastMatchesRef.current : list, query: newQuery})
    },
    [list, createWorker],
  )

  useEffect(() => {
    createWorker()
    return () => workerRef.current?.terminate()
  }, [createWorker])

  useEffect(() => {
    postWorkerMessage(query)
  }, [query, postWorkerMessage])

  if (!workerPath) return [[], false, () => {}]

  return [matches, searching, clearMatches]
}

export function useReposIndexingState(nwos: string[]): [IndexingState, () => void] {
  const client = useQueryClient()

  const invalidateIndexingStatus = useCallback(
    () => Promise.all(nwos.map(nwo => client.invalidateQueries({queryKey: ['repo-indexing-state', nwo]}))),
    [client, nwos],
  )

  const results = useQueries({
    queries: nwos.map(nwo => ({
      queryKey: ['copilot-chat', 'repos-indexing-state', nwo],
      queryFn: () => fetchIndexingStatus(nwo),
      placeholderData: {
        requestStatus: CanIndexStatus.Unknown,
        code: TopicIndexStatus.Unknown,
        docs: TopicIndexStatus.Unknown,
      },
      staleTime: Infinity,
    })),
  })

  const {mutate: triggerIndexingForRepos} = useMutation({
    mutationKey: ['repos-indexing-state'],
    mutationFn: () => triggerIndexing(nwos),
    onSuccess: invalidateIndexingStatus,
  })

  const aggregatedIndexingStatus = aggregateResults(results.map(r => r.data!))

  // If any repo is "indexing" and we have not encountered an error, we consider indexing to be in progress
  const isIndexingInProgress =
    aggregatedIndexingStatus.code === TopicIndexStatus.Indexing &&
    aggregatedIndexingStatus.requestStatus !== CanIndexStatus.IndexingError

  useInterval(() => void invalidateIndexingStatus(), isIndexingInProgress ? 10000 : 0)

  return [aggregatedIndexingStatus, () => triggerIndexingForRepos()]
}

export function useRepoIndexingState(nwo: string): [IndexingState, () => void] {
  const client = useQueryClient()

  const invalidateIndexingStatus = useCallback(
    () => Promise.resolve(client.invalidateQueries({queryKey: ['repo-indexing-state', nwo]})),
    [client, nwo],
  )

  const result = useQuery({
    queryKey: ['copilot-chat', 'repo-indexing-state', nwo],
    queryFn: () => fetchIndexingStatus(nwo),
    placeholderData: {
      requestStatus: CanIndexStatus.Unknown,
      code: TopicIndexStatus.Unknown,
      docs: TopicIndexStatus.Unknown,
    },
    staleTime: Infinity,
  })

  const {mutate: triggerIndexingForRepos} = useMutation({
    mutationKey: ['repo-indexing-state'],
    mutationFn: () => triggerIndexing([nwo]),
    onSuccess: invalidateIndexingStatus,
  })

  const indexingStatus = result.data!

  // If repo is "indexing" and we have not encountered an error, we consider indexing to be in progress
  const isIndexingInProgress =
    indexingStatus.code === TopicIndexStatus.Indexing && indexingStatus.requestStatus !== CanIndexStatus.IndexingError

  useInterval(() => void invalidateIndexingStatus(), isIndexingInProgress ? 10000 : 0)

  return [indexingStatus, () => triggerIndexingForRepos()]
}

export function useChatWithKb(ids: number[]): boolean {
  const result = useQuery({
    queryKey: ['copilot-chat', 'repos-indexing-state', ids],
    queryFn: () => fetchKbChatStatus(ids),
    staleTime: Infinity,
  })

  if (result.isError) {
    return false
  }

  return !!result.data?.canChat
}

export function useShowTopicPicker() {
  const state = useChatState()
  const manager = useChatManager()

  useEffect(() => {
    manager.showTopicPicker(
      (!state.selectedThreadID || state.mode === 'assistive') && state.messages.length === 0 && !state.currentTopic,
    )
    // When the thread updates, see if we need to show a blank thread.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.selectedThreadID])
}

export function useResizablePanel() {
  const initialPanelHeight = copilotLocalStorage.getPanelHeight()
  const initialPanelWidth = copilotLocalStorage.getPanelWidth()
  const resizeStartY = useRef<number | null>(null)
  const resizeStartHeight = useRef(initialPanelHeight)
  const newHeight = useRef(initialPanelHeight)
  const resizeStartX = useRef<number | null>(null)
  const resizeStartWidth = useRef(initialPanelWidth)
  const newWidth = useRef(initialPanelWidth)
  const [panelHeight, setPanelHeight] = useState(initialPanelHeight)
  const [panelWidth, setPanelWidth] = useState(initialPanelWidth)
  const remSize = useRef(0)

  useEffect(() => {
    remSize.current = parseFloat(getComputedStyle(document.documentElement).fontSize)
  }, [])

  const getPanelHeight = (height: number) => {
    return Math.min(Math.max(height, MIN_PANEL_HEIGHT), window.innerHeight - remSize.current)
  }

  const getPanelWidth = (width: number) => {
    return Math.min(Math.max(width, MIN_PANEL_WIDTH), window.innerWidth - 2 * remSize.current)
  }

  const resize = useCallback((e: MouseEvent) => {
    if (resizeStartY.current !== null) {
      const dy = resizeStartY.current - e.clientY
      const height = getPanelHeight(resizeStartHeight.current + dy)
      setPanelHeight(height)
      newHeight.current = height
    }
    if (resizeStartX.current !== null) {
      const dx = resizeStartX.current - e.clientX
      const width = getPanelWidth(resizeStartWidth.current + dx)
      setPanelWidth(width)
      newWidth.current = width
    }
  }, [])

  const stopResize = useCallback(() => {
    window.removeEventListener('mousemove', resize)
    window.removeEventListener('mouseup', stopResize)
    if (resizeStartY.current !== null) {
      // use newHeight ref since panelHeight might not be updated yet.
      copilotLocalStorage.setPanelHeight(newHeight.current)
      resizeStartY.current = null
    }
    if (resizeStartX.current !== null) {
      copilotLocalStorage.setPanelWidth(newWidth.current)
      resizeStartX.current = null
    }
  }, [resize])

  const startResize = useCallback(
    (e: React.MouseEvent, horizontal: boolean, vertical: boolean) => {
      if (e.button === 0) {
        e.preventDefault()
        if (vertical) {
          resizeStartY.current = e.clientY
          resizeStartHeight.current = panelHeight
        }
        if (horizontal) {
          resizeStartX.current = e.clientX
          resizeStartWidth.current = panelWidth
        }
        window.addEventListener('mousemove', resize)
        window.addEventListener('mouseup', stopResize)
      }
    },
    [panelHeight, panelWidth, resize, stopResize],
  )

  const onResizerKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key === 'ArrowUp') {
        const newPanelHeight = getPanelHeight(panelHeight + 4)
        setPanelHeight(newPanelHeight)
        copilotLocalStorage.setPanelHeight(newPanelHeight)
        e.preventDefault()
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      } else if (e.key === 'ArrowDown') {
        const newPanelHeight = getPanelHeight(panelHeight - 4)
        setPanelHeight(newPanelHeight)
        copilotLocalStorage.setPanelHeight(newPanelHeight)
        e.preventDefault()
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      } else if (e.key === 'ArrowRight') {
        const newPanelWidth = getPanelWidth(panelWidth - 4)
        setPanelWidth(newPanelWidth)
        copilotLocalStorage.setPanelWidth(newPanelWidth)
        e.preventDefault()
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      } else if (e.key === 'ArrowLeft') {
        const newPanelWidth = getPanelWidth(panelWidth + 4)
        setPanelWidth(newPanelWidth)
        copilotLocalStorage.setPanelWidth(newPanelWidth)
        e.preventDefault()
      }
    },
    [panelHeight, panelWidth],
  )

  return {panelWidth, panelHeight, startResize, onResizerKeyDown}
}

export function useSidePanelPositionStyles(open: boolean): {left?: string; bottom?: string} {
  const [positionStyles, setPositionStyles] = useState({})
  const panelRef = useChatPanelReferenceContext()

  useEffect(() => {
    if (open && (panelRef?.current?.clientWidth || 480) + 480 >= window.innerWidth) {
      setPositionStyles({
        left: `${window.innerWidth - (panelRef?.current?.clientWidth || 480)}px !important`,
        bottom: '64px',
      })
    } else {
      setPositionStyles({})
    }
  }, [open, panelRef])

  return positionStyles
}

async function fetchIndexingStatus(nwo: string): Promise<IndexingState> {
  const res = await fetch(`/search/check_indexing_status?nwo=${encodeURIComponent(nwo)}`, {
    headers: {Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
  })

  if (!res.ok) {
    return {
      requestStatus: CanIndexStatus.RequestFailed,
      code: TopicIndexStatus.Unknown,
      docs: TopicIndexStatus.Unknown,
    }
  }

  const data = (await res.json()) as IndexingStateResponse

  return {
    requestStatus: data.can_index,
    code: data.code_status,
    docs: data.docs_status,
    remainingRepoIndexTokens: data.remaining_repo_index_tokens,
  }
}

async function triggerIndexing(nwos: string[]) {
  const nwosParam =
    nwos.length === 1 ? `nwo=${encodeURIComponent(nwos[0]!)}` : `nwos=${encodeURIComponent(JSON.stringify(nwos))}`

  return verifiedFetch(`/search/index_embeddings?${nwosParam}&index_code=${true}`, {method: 'POST'})
}

async function fetchKbChatStatus(ids: number[]): Promise<{canChat: boolean} | undefined> {
  const res = await fetch(
    `/github-copilot/docs/docsets/kb_indexed_repos?ids=${encodeURIComponent(JSON.stringify(ids))}`,
    {
      headers: {Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
    },
  )

  if (!res.ok) {
    return {canChat: false}
  }

  const data = (await res.json()) as {canChat: boolean}

  return data
}

function aggregateResults(repoStates: IndexingState[]): IndexingState {
  return {
    requestStatus: aggregateCanIndexStatuses(repoStates.map(s => s.requestStatus)),
    code: aggregateTopicIndexStatuses(repoStates.map(s => s.code)),
    docs: aggregateTopicIndexStatuses(repoStates.map(s => s.docs)),
    remainingRepoIndexTokens: repoStates[0]?.remainingRepoIndexTokens,
  }
}

function aggregateTopicIndexStatuses(statuses: TopicIndexStatus[]): TopicIndexStatus {
  // if every repo is "indexed", return "indexed"
  if (statuses.every(s => s === TopicIndexStatus.Indexed)) return TopicIndexStatus.Indexed
  // If every repo is "unindexed", return "unindexed"
  if (statuses.every(s => s === TopicIndexStatus.Unindexed)) return TopicIndexStatus.Unindexed
  // If any repo is "indexing", return "indexing"
  if (statuses.some(s => s === TopicIndexStatus.Indexing)) return TopicIndexStatus.Indexing
  // If any repo is "unindexed", we don't have any "indexing" repos, and not all repos are indexed/unindexed, return "partially indexed"
  if (statuses.some(s => s === TopicIndexStatus.Unindexed)) return TopicIndexStatus.PartiallyIndexed
  // Fallback to "unknown"
  return TopicIndexStatus.Unknown
}

function aggregateCanIndexStatuses(statuses: CanIndexStatus[]): CanIndexStatus {
  // If we don't have any statuses, return unknown
  if (statuses.length === 0) return CanIndexStatus.Unknown
  // If any status is error, return "indexing error"
  if (statuses.some(s => errorStatuses.includes(s))) return CanIndexStatus.IndexingError
  // If all statuses are "can index", return "can index"
  if (statuses.every(s => s === CanIndexStatus.CanIndex)) return CanIndexStatus.CanIndex
  // If all statuses are "unknown", return "unknown"
  if (statuses.every(s => s === CanIndexStatus.Unknown)) return CanIndexStatus.Unknown
  // Fallback to "unknown"
  return CanIndexStatus.Unknown
}

function useInterval(callback: () => void, delay: number) {
  const intervalRef = useRef<number | undefined>(undefined)
  const savedCallback = useRef(callback)
  useEffect(() => {
    savedCallback.current = callback
  }, [callback])
  useEffect(() => {
    const tick = () => savedCallback.current()
    if (delay > 0) {
      intervalRef.current = window.setInterval(tick, delay)
      return () => window.clearInterval(intervalRef.current)
    }
  }, [delay])
  return intervalRef
}
