import {LabelFragment, LabelPickerGraphqlQuery} from '@github-ui/item-picker/LabelPicker'
import type {LabelPickerLabel$data, LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import type {LabelPickerQuery} from '@github-ui/item-picker/LabelPickerQuery.graphql'
import {useQuery} from '@github-ui/react-query'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {useRelayEnvironment} from 'react-relay'
import {readInlineData} from 'relay-runtime'

export type Label = LabelPickerLabel$data

export function useLabelsQuery({owner, repo, labels}: {owner?: string; repo?: string; labels?: string[]}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-labels', JSON.stringify(environment), owner, repo, labels],
    queryFn: async () => {
      if (!owner || !repo || !labels) return []

      const data = await clientSideRelayFetchQueryRetained<LabelPickerQuery>({
        environment,
        query: LabelPickerGraphqlQuery,
        variables: {
          owner,
          repo,
          shouldQueryByNames: true,
          labelNames: labels.join(','),
          count: labels.length,
        },
      }).toPromise()

      return (data?.repository?.labelsByNames?.nodes ?? [])
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<LabelPickerLabel$key>(LabelFragment, node)
        })
    },
  })
}
