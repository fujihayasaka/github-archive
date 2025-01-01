import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useNavigate} from 'react-router-dom'

export function SpaceDeletedBanner() {
  return (
    <Banner
      title="Chat is disabled"
      variant="warning"
      description="Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization."
      hideTitle
    />
  )
}

export function SpaceSizeExceededBanner({customCopilot}: {customCopilot: CustomCopilot | undefined}) {
  const navigate = useNavigate()

  return (
    customCopilot && (
      <Banner
        title="Chat is disabled"
        variant="critical"
        description="You've exceeded the size limit for this space. Remove some references to continue chatting."
        hideTitle
        primaryAction={
          <LinkButton
            as="a"
            href={getCopilotSpacePath(customCopilot)}
            onClick={event => {
              event.preventDefault()
              navigate(getCopilotSpacePath(customCopilot))
            }}
          >
            Edit
          </LinkButton>
        }
      />
    )
  )
}

export function ReferenceSizeExceededBanner() {
  return (
    <Banner
      title="Reference size exceeded"
      variant="critical"
      description="You've exceeded the size limit for this space. Remove some references to continue."
      hideTitle
      className="mb-3"
    />
  )
}

export function AssociatedRepositoryReferenceNotFoundBanner() {
  return (
    <Banner
      title="Reference not found"
      variant="critical"
      description="We couldn't access that repository. Make sure it exists and that you have permission to use it."
      hideTitle
      className="mb-3"
    />
  )
}
