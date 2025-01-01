import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from 'react-router-dom'

import {fileUrl} from '../utilities/urls'
import type {DisplayTaskData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function useSuggestionNavigation() {
  const {path, repo, pullRequestNumber} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const navigate = useNavigate()

  const navigateToSuggestionPath = (suggestion: DisplayTaskData) => {
    if (path !== suggestion?.path) {
      const suggestionFileUrl = fileUrl({
        owner: repo.ownerLogin,
        repo: repo.name,
        path: suggestion.path,
        pullNumber: pullRequestNumber,
        location: window.location,
      })
      navigate(suggestionFileUrl)
    }
  }
  return navigateToSuggestionPath
}
