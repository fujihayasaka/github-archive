import {useCurrentRepository} from '@github-ui/current-repository'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import type {GroupedDiffs} from '../utilities/diff-analysis'
import {taskDiffUrl} from '../utilities/urls'

export function useDiffCategorization({
  analyzeDiffs = false,
  detectRisk = false,
}: {
  analyzeDiffs?: boolean
  detectRisk?: boolean
}) {
  const repo = useCurrentRepository()
  const {pullRequest} = useCurrentPullRequest()

  const {data, isLoading} = useQuery({
    queryKey: ['diff-analysis', repo.ownerLogin, repo.name, pullRequest.number, analyzeDiffs, detectRisk],
    queryFn: async () => {
      const res = await verifiedFetchJSON(
        taskDiffUrl({
          owner: repo.ownerLogin,
          repo: repo.name,
          pullNumber: pullRequest.number,
          analyzeDiffs,
          detectRisk,
        }),
      )

      if (!res.ok) throw new Error(`Failed to fetch diff categorization: ${res.status}`)

      return (await res.json()) as GroupedDiffs
    },
    meta: {action: 'get-diff-analysis'},
  })

  return {data, isLoading}
}
