import {IS_SERVER} from '@github-ui/ssr-utils'
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
export function getQueryClient() {
  /**
   * Protection against leaking data, by ensuring we don't use a cached queryClient in SSR environments by avoiding a shared queryClient
   *
   * https://tanstack.com/query/latest/docs/framework/react/guides/advanced-ssr#initial-setup
   */
  if (IS_SERVER) return createQueryClient()
  return (browserQueryClient ??= createQueryClient())
}
