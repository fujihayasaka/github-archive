import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {
  findCustomCopilot,
  getCopilotSpacePath,
  isCopilotSpacePath,
  isCopilotSpacesPage,
} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {replaceNavigationBreadcrumbs} from '@github-ui/global-navigation'

export const useGlobalNavigation = () => {
  const state = useChatState()
  const selectedCopilotSpaceId = useSelectedCustomCopilotId()
  const selectedCopilotSpace = findCustomCopilot(state.customCopilots, selectedCopilotSpaceId)
  const includeSpacesCrumb = isCopilotSpacesPage() || selectedCopilotSpace
  const includeSpaceNameCrumb = !isCopilotSpacePath() && selectedCopilotSpace

  const updateGlobalNavigationBreadcrumbs = () => {
    const crumbs = [
      {
        label: 'Copilot',
        href: '/copilot',
      },
    ]

    if (includeSpacesCrumb) {
      crumbs.push({
        label: 'Spaces',
        href: COPILOT_SPACES_PATH,
      })
    }

    if (includeSpaceNameCrumb && selectedCopilotSpace) {
      crumbs.push({
        label: selectedCopilotSpace.name,
        href: getCopilotSpacePath(selectedCopilotSpace),
      })
    }

    replaceNavigationBreadcrumbs(crumbs)
  }

  return {updateGlobalNavigationBreadcrumbs}
}
