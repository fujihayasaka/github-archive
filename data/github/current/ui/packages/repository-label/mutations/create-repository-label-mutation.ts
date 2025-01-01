import {commitMutation, graphql} from 'react-relay'

import type {Environment} from 'relay-runtime'
import type {
  createRepositoryLabelMutation,
  createRepositoryLabelMutation$data,
  createRepositoryLabelMutation$variables,
} from './__generated__/createRepositoryLabelMutation.graphql'

export type CreateRepositoryLabelResponse = createRepositoryLabelMutation$data['createLabel']

export function commitCreateRepositoryLabelMutation({
  environment,
  input,
  connectionId,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: createRepositoryLabelMutation$variables['input']
  connectionId: string
  onError: (error: Error) => void
  onCompleted: (response: createRepositoryLabelMutation$data) => void
}) {
  return commitMutation<createRepositoryLabelMutation>(environment, {
    mutation: graphql`
      mutation createRepositoryLabelMutation($input: CreateLabelInput!, $connection: ID!) {
        createLabel(input: $input) {
          label @prependNode(connections: [$connection], edgeTypeName: "LabelEdge") {
            id
            ...LabelRow
          }
          errors {
            message
          }
        }
      }
    `,
    variables: {input, connection: connectionId},
    onError: error => onError?.(error),
    onCompleted: response => onCompleted?.(response),
    updater: store => {
      if (!connectionId) return
      const conn = store.get(connectionId)
      if (!conn) return
      const count = (conn.getValue('totalCount') as number) ?? 0
      conn.setValue(count + 1, 'totalCount')
    },
  })
}
