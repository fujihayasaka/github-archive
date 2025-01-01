import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {reposPickerRepositoriesPath} from '../paths'
import type {FetchRepositoriesData} from '../types'

export function useQueryRepositories({
  orgLogin,
  enabled = true,
  query = '',
}: {
  orgLogin?: string
  enabled?: boolean
  query?: string
}) {
  return useQuery<FetchRepositoriesData>({
    queryKey: ['repos-picker', 'repositories', orgLogin, query],
    queryFn: async () => {
      const fetchRepositoriesUrl = reposPickerRepositoriesPath({orgLogin, query})

      const response = await verifiedFetchJSON(fetchRepositoriesUrl)
      if (!response.ok) {
        throw new Error('Error fetching repositories')
      } else {
        return await response.json()
      }
    },
    enabled,
  })
}
