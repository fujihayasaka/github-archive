import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export interface SearchData<T> {
  items: T[]
  totalCount: number
}

export function useQuerySearch<T>({searchUrl, enabled = true}: {searchUrl: string; enabled?: boolean}) {
  return useQuery<SearchData<T>>({
    queryKey: [searchUrl],
    queryFn: async () => {
      const response = await verifiedFetchJSON(searchUrl)
      if (!response.ok) {
        throw new Error('Error fetching search results')
      } else {
        return await response.json()
      }
    },
    enabled,
  })
}
