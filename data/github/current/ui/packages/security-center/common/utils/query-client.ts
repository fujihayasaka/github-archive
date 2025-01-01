import {QueryClient, type QueryClientConfig} from '@tanstack/react-query'

export function createQueryClient(options?: QueryClientConfig): QueryClient {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: 3, // retry up to 3 failures
        refetchOnWindowFocus: false,
        staleTime: 1000 * 60 * 5, // 5 minute stale time before cache invalidation
        ...options?.defaultOptions?.queries,
      },
      ...options?.defaultOptions,
    },
    ...options,
  })

  return queryClient
}
