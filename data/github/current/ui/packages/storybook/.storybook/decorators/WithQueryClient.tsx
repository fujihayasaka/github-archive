import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/react-core/query-client'
import type {Decorator} from '@storybook/react'

export const withQueryClient: Decorator = (Story, context) => {
  const queryClient = getQueryClient()
  // clear the query client between stories
  queryClient.clear()

  return <QueryClientProvider client={queryClient}>{Story(context)}</QueryClientProvider>
}
