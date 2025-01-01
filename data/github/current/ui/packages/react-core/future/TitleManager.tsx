import {useEffect} from 'react'
import {addGitHubToTitle, setTitle} from '@github-ui/document-metadata'
import {useQueryClient} from '@github-ui/react-query'
import {useRouteMatches} from './query-route'

export function TitleManager() {
  const matches = useRouteMatches()
  const queryClient = useQueryClient()
  useEffect(() => {
    // This means we're checking the "leaf nodes" first.
    // As soon as we find a title, we can break out of the loop.
    for (const match of matches.toReversed()) {
      if (!match.data?.route) continue
      const config = match.data?.queries.mainQuery
      if (!config) continue
      const cached = queryClient.getQueryData(config.queryConfig.queryKey) as {title?: string}
      if (cached.title) {
        setTitle(addGitHubToTitle(cached.title))
        break
      }
    }
  }, [matches, queryClient])

  return null
}
