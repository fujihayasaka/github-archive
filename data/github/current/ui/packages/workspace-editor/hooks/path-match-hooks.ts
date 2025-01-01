import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useMatch, useResolvedPath} from 'react-router-dom'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {fileUrl} from '../utilities/urls'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function useIsFileEditorPage(): boolean {
  const repo = useCurrentRepository()
  const {showOverview} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const filePath = fileUrl({
    owner: repo.ownerLogin,
    repo: repo.name,
    pullNumber: pullRequest.number,
    path: '*',
  })

  const resolved = useResolvedPath(filePath)
  return !!useMatch({path: resolved.pathname, end: true}) && !showOverview
}
