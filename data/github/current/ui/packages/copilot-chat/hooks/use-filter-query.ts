import {useQuery} from '@github-ui/react-query'

import {useChatState} from '../utils/CopilotChatContext'

interface FilterWorkerResponse {
  query: string
  list: string[]
}

async function workerFilter(data: string[], query: string, workerPath: string, abortSignal: AbortSignal) {
  return new Promise<string[]>((resolve, reject) => {
    if (!window.Worker) {
      // If workers aren't available, just use a simple filter, but delegate it to try to avoid blocking the main thread
      setTimeout(() => resolve(data.filter(item => item.includes(query))))
      return
    }

    const worker = new Worker(workerPath)

    worker.addEventListener('message', (message: {data: FilterWorkerResponse}) => resolve(message.data.list))
    worker.addEventListener('error', error => reject(new Error(`Worker error: ${error.message}`)))
    abortSignal.addEventListener('abort', () => {
      worker.terminate()
      reject(new Error('Worker aborted'))
    })

    worker.postMessage({baseList: data, query})
  })
}

/** Asynchronously filter big data in a Web Worker thread. */
export function useFilterQuery(list: string[] | null, query: string) {
  const {findFileWorkerPath: workerPath} = useChatState()

  return useQuery({
    queryKey: ['copilot-worker-filter', workerPath, list, query],
    queryFn: async ({signal}) => {
      if (!list) return []
      if (query.length === 0) return list

      return workerFilter(list, query, workerPath, signal)
    },
    enabled: list !== null,
    // This data cannot get stale - the result of filtering a list by a given query cannot change.
    staleTime: Infinity,
    // 10 seconds is fairly aggressive, but these lists could be huge (that's the whole point of using a worker) and
    // consume tons of memory, so we don't want them around any longer than necessary.
    gcTime: 10_000,
    // No need to be online for this.
    networkMode: 'always',
    // If the worker fails, a retry is very unlikely to fix it since nothing will have changed.
    retry: false,
    // Keep showing previous data while new data is filtering
    placeholderData: prev => prev,
  })
}
