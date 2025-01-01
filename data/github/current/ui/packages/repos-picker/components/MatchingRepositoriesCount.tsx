import {human} from '@github-ui/formatters'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Link} from '@primer/react'

import {reposPickerRepositoriesCountPath} from '../paths'
import type {PickerScope} from '../types'

interface Props {
  query?: string
  href?: string
  scope: PickerScope
}

interface FetchRepositoriesCountData {
  totalCount: number
}

export function MatchingRepositoriesCount({query, scope, href}: Props) {
  const {data, isLoading} = useQuery<FetchRepositoriesCountData>({
    queryKey: ['repos-picker', 'repositories', 'count', scope, query],
    queryFn: async () => {
      const fetchUrl = reposPickerRepositoriesCountPath({scope, query: query || ''})
      const response = await verifiedFetchJSON(fetchUrl)
      if (!response.ok) {
        throw new Error('Error fetching repositories')
      } else {
        return await response.json()
      }
    },
    enabled: !!query,
  })

  if (isLoading || !data) {
    return null
  }

  const message = `Matching ${human(data.totalCount)} ${data.totalCount === 1 ? 'repository' : 'repositories'}`

  if (href) {
    return (
      <Link className="color-fg-muted text-small" inline target="_blank" rel="noopener noreferrer" href={href}>
        {message}
      </Link>
    )
  }

  return <span className="color-fg-muted text-small">{message}</span>
}
