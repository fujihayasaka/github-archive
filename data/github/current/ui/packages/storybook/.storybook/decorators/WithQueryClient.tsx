import type {StoryContext} from './types'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/react-core/query-client'

export const withQueryClient = (Story: React.FC<React.PropsWithChildren<StoryContext>>, context: StoryContext) => {
  const queryClient = getQueryClient()
  // clear the query client between stories
  queryClient.clear()

  return <QueryClientProvider client={queryClient}>{Story(context)}</QueryClientProvider>
}
