// a utility hook that provides a stateful access to the current viewer

import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useUser} from '@github-ui/use-user'
import {useState, useEffect} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {graphql, readInlineData} from 'relay-runtime'
import type {AssigneePickerAssignee$key} from '../components/__generated__/AssigneePickerAssignee.graphql'
import {type Assignee, AssigneeFragment} from '../components/AssigneePicker'
import type {
  useViewerSafeViewerQuery,
  useViewerSafeViewerQuery$data,
} from './__generated__/useViewerSafeViewerQuery.graphql'

// it will use the relay store to first look for the data and do a query over the network if needed
export function useViewer(): Assignee | null {
  const environment = useRelayEnvironment()
  const {currentUser} = useUser()
  // before making a request, try get the viewer via the `useUser` hook that can provide this value
  // based on the app payload - this is not always possible, e.g. in memex the app payload is not
  // used so a request must be sent in this case
  const [viewer, setViewer] = useState<Assignee | null>(currentUser as Assignee | null)

  useEffect(() => {
    if (!IS_SERVER && !viewer) {
      clientSideRelayFetchQueryRetained<useViewerSafeViewerQuery>({
        environment,
        query: graphql`
          query useViewerSafeViewerQuery {
            safeViewer {
              ...AssigneePickerAssignee
            }
          }
        `,
        variables: {},
      }).subscribe({
        next: (data: useViewerSafeViewerQuery$data) => {
          if (data.safeViewer) {
            // eslint-disable-next-line no-restricted-syntax
            const currentViewer = readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, data.safeViewer)
            setViewer(currentViewer)
          }
        },
      })
    }
  }, [environment, viewer])

  return viewer
}
