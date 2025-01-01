import {QueryClient} from '@tanstack/react-query'

import {queryKeyHashFn} from './query-key-hash-fn'

function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        refetchOnWindowFocus: false,
        retry: false,
        networkMode: 'always',
        queryKeyHashFn,
      },
      mutations: {
        networkMode: 'always',
      },
    },
  })
}

let browserQueryClient: QueryClient
export function getQueryClient(): QueryClient {
  return (browserQueryClient ??= createQueryClient())
}
