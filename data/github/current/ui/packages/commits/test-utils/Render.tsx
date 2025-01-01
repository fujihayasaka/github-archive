import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {SelectedDiffRowRangeContextProvider} from '@github-ui/diff-lines'
import {render} from '@github-ui/react-core/test-utils'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'

import type {CommitPayload} from '../types/commit-types'

export function renderCommit(children: React.ReactNode, payload: CommitPayload) {
  const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

  return render(
    <RelayEnvironmentProvider environment={relayEnvironment}>
      <CurrentRepositoryProvider repository={payload.repo}>
        <SelectedDiffRowRangeContextProvider>{children}</SelectedDiffRowRangeContextProvider>
      </CurrentRepositoryProvider>
    </RelayEnvironmentProvider>,
    {
      routePayload: payload,
    },
  )
}
