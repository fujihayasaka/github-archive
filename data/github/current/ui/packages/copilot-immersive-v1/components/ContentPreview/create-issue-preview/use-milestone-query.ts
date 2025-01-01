import {MilestoneFragment, MilestonePickerSearchGraphqlQuery} from '@github-ui/item-picker/MilestonePicker'
import type {MilestonePickerMilestone$key} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import type {MilestonePickerSearchQuery} from '@github-ui/item-picker/MilestonePickerSearchQuery.graphql'
import {useQuery} from '@github-ui/react-query'
import {useRelayEnvironment} from 'react-relay'
import {fetchQuery, readInlineData} from 'relay-runtime'

export function useMilestoneQuery({
  owner,
  repo,
  milestone,
}: {
  owner: string | undefined
  repo: string | undefined
  milestone: string | undefined
}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-milestones', JSON.stringify(environment), owner, repo, milestone],
    queryFn: async () => {
      if (!owner || !repo || !milestone) return null

      const data = await fetchQuery<MilestonePickerSearchQuery>(environment, MilestonePickerSearchGraphqlQuery, {
        owner,
        repo,
        query: milestone,
        count: 1,
      }).toPromise()

      const fetchedMilestones = (data?.repository?.milestones?.nodes || [])
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<MilestonePickerMilestone$key>(MilestoneFragment, node)
        })

      return fetchedMilestones[0] ?? null
    },
  })
}
