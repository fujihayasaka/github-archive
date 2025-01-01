import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'

import type {PullRequestData, WorkspaceEditorPullRequestPayload} from '../utilities/workspace-editor-types'

interface PullRequestContextData {
  pullRequest: PullRequestData
  setPullRequest: (pullRequest: PullRequestData) => void
}

const PullRequestContext = createContext<PullRequestContextData | undefined>(undefined)

export function CurrentPullRequestProvider({children}: PropsWithChildren) {
  const {pullRequest: routePullRequest} = useRoutePayload<WorkspaceEditorPullRequestPayload>()
  const [pullRequest, setPullRequest] = useState<PullRequestData>(routePullRequest)

  const value = useMemo(
    () => ({
      pullRequest,
      setPullRequest,
    }),
    [pullRequest, setPullRequest],
  )

  return <PullRequestContext.Provider value={value}>{children}</PullRequestContext.Provider>
}

export function useCurrentPullRequest() {
  const context = useContext(PullRequestContext)
  if (!context) {
    throw new Error('useCurrentPullRequest must be used within an CurrentPullRequestProvider')
  }
  return context
}
