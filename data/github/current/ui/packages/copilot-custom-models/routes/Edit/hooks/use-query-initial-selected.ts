import {useQuery} from '@tanstack/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {PipelineRepo} from '../../../types'

interface UseQueryInitialSelectedProps {
  repoListPath: string
}

interface UseQueryInitialSelected {
  fetchSelected: () => void
  initialSelectedRepos: PipelineRepo[] | undefined
  isLoadingSelected: boolean
}

export function useQueryInitialSelected({repoListPath}: UseQueryInitialSelectedProps): UseQueryInitialSelected {
  const {
    data: initialSelectedRepos,
    isLoading: isLoadingSelected,
    refetch: fetchSelected,
  } = useQuery({
    enabled: false,
    queryKey: ['initial-selected-repos', repoListPath],
    queryFn: async () => {
      const path = `${repoListPath}?limit_by=0`
      const response: Response = await verifiedFetchJSON(path, {method: 'GET'})
      if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`)

      const selectedRepos = (await response.json()).data as PipelineRepo[]

      return selectedRepos
    },
  })

  return {fetchSelected, initialSelectedRepos, isLoadingSelected}
}
