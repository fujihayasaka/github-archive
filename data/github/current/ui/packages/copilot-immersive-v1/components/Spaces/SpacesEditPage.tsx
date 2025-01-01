import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpacePath, useRouteSpaceId} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {
  CustomCopilotNotFoundError,
  CustomCopilotSSOError,
  useFetchCustomCopilot,
} from '@github-ui/custom-copilots/hooks'
import {useNavigate} from '@github-ui/use-navigate'

import {ConversationLoader} from '../ConversationLoader'
import {SpaceNotFoundComponent} from '../SpaceNotFoundComponent'
import {SpacesForm} from './SpacesForm'

export function SpacesEditPage() {
  const navigate = useNavigate()
  const customCopilotId = useRouteSpaceId()

  const {isPending, data: currentSpacePayload, error} = useFetchCustomCopilot(customCopilotId)
  const copilotSpace = currentSpacePayload

  function handleCancel() {
    navigate(getCopilotSpacePath(copilotSpace as CustomCopilot))
  }

  if (error instanceof CustomCopilotNotFoundError) {
    return <SpaceNotFoundComponent />
  } else if (error instanceof CustomCopilotSSOError) {
    return <SpaceNotFoundComponent protectedOrganizations={error.protectedOrganizations} />
  }

  if (isPending) {
    return <ConversationLoader />
  }

  return <SpacesForm copilotSpace={copilotSpace} onCancel={handleCancel} />
}
