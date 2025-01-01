import {
  IssueTypeFragment,
  IssueTypePickerGraphqlQuery,
  IssueTypePickerPaginatedFragment,
} from '@github-ui/item-picker/IssueTypePicker'
import type {IssueTypePickerIssueType$key} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import type {IssueTypePickerPaginated$key} from '@github-ui/item-picker/IssueTypePickerPaginated.graphql'
import type {IssueTypePickerQuery} from '@github-ui/item-picker/IssueTypePickerQuery.graphql'
import {useQuery} from '@github-ui/react-query'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {useRelayEnvironment} from 'react-relay'
import {readInlineData} from 'relay-runtime'

const ORGANIZATION_ISSUE_TYPES_LIMIT = 25

export function useIssueTypesQuery({owner, repo}: {owner: string | undefined; repo: string | undefined}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-issue-types', JSON.stringify(environment), owner, repo],
    queryFn: async () => {
      if (!owner || !repo) return []

      const data = await clientSideRelayFetchQueryRetained<IssueTypePickerQuery>({
        environment,
        query: IssueTypePickerGraphqlQuery,
        variables: {owner, repo, issueTypesPageSize: ORGANIZATION_ISSUE_TYPES_LIMIT},
      }).toPromise()

      if (!data?.repository) {
        return []
      }

      // eslint-disable-next-line no-restricted-syntax
      const issueTypesData = readInlineData<IssueTypePickerPaginated$key>(
        IssueTypePickerPaginatedFragment,
        data.repository,
      )

      return (issueTypesData?.issueTypes?.edges?.flatMap(a => a?.node) ?? [])
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, node)
        })
    },
  })
}
