import {addGitHubToTitle, setTitle} from '@github-ui/document-metadata'
import type {QueryClient} from '@github-ui/react-query'
import {useQueryClient} from '@github-ui/react-query'
import {useEffect} from 'react'

import {type QueryOptionsWithKey, useRouteMatches} from './query-route'

export function TitleManager() {
  const matches = useRouteMatches()
  const queryClient = useQueryClient()
  useEffect(() => {
    // Avoid Array.prototype.toReversed until it's been around a bit longer for the
    // sake of older browsers (e.g. Chrome <=109)
    for (const match of [...matches].reverse()) {
      if (!match.data?.route) continue
      const config = match.data?.queries.mainQuery
      if (!config) continue
      const title = getTitleFromQueryClient(queryClient, config.queryConfig)
      if (title) {
        setTitle(addGitHubToTitle(title))
        break
      }
    }
  }, [matches, queryClient])

  return null
}

export function getTitleFromQueryClient(
  queryClient: QueryClient,
  queryConfig: QueryOptionsWithKey,
): string | undefined {
  const cached = queryClient.getQueryData(queryConfig.queryKey) as {title?: string} | {meta?: {title: string}}
  if ('title' in cached && cached.title) {
    return cached?.title
  } else if ('meta' in cached && cached.meta) {
    return cached.meta.title
  }
}
