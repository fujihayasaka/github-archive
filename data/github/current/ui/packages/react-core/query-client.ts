import {QueryClient} from '@tanstack/react-query'

function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        refetchOnWindowFocus: false,
        retry: false,
        networkMode: 'always',
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
