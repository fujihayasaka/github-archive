import {QueryClient} from '@tanstack/react-query'

export function getQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        refetchOnWindowFocus: false,
        retry: false,
      },
      mutations: {
        // Always make requests to ensure we show an error when the user is offline
        networkMode: 'always',
      },
    },
  })
}
