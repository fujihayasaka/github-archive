import {type Assignee, AssigneeFragment, SearchAssignableRepositoryUsers} from '@github-ui/item-picker/AssigneePicker'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import type {AssigneePickerSearchAssignableRepositoryUsersQuery} from '@github-ui/item-picker/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import {getActorCapabilities} from '@github-ui/item-picker/utils/assignee-picker'
import {useQuery} from '@github-ui/react-query'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {useRelayEnvironment} from 'react-relay'
import {readInlineData} from 'relay-runtime'

export function useAssigneesQuery({
  owner,
  repo,
  assignees,
}: {
  owner: string | undefined
  repo: string | undefined
  assignees: string[] | undefined
}) {
  const environment = useRelayEnvironment()
  const capabilities = getActorCapabilities({includeAuthorableBots: false, includeAssignableBots: true})

  return useQuery({
    queryKey: ['copilot-immersive-assignees', JSON.stringify(environment), capabilities, owner, repo, assignees],
    queryFn: async () => {
      if (!owner || !repo || !assignees) return []

      const data = await clientSideRelayFetchQueryRetained<AssigneePickerSearchAssignableRepositoryUsersQuery>({
        environment,
        query: SearchAssignableRepositoryUsers,
        variables: {
          owner,
          name: repo,
          loginNames: assignees.join(',') ?? [],
          first: assignees.length ?? 0,
          capabilities,
        },
      }).toPromise()

      return (data?.repository?.suggestedActors?.nodes ?? [])
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, node) as Assignee
        })
    },
  })
}
