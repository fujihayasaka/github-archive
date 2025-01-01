import {Navigation, NavigationSubItem} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {useChatStateValues} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH, COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {
  CREATE_CUSTOM_COPILOTS_URL,
  getCopilotSpacePath,
  isCopilotSpacesListPath,
  useAvailableCustomCopilots,
} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useNavigate} from '@github-ui/use-navigate'
import {PlusIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useCallback} from 'react'

import {useNavigateToNewThread} from '../../hooks/use-navigate-to-new-thread'
import SpacesIcon from '../Icons/SpacesIcon'
import {CopilotSpacesMenu} from './SpaceMenu'
import styles from './SpacesNavigation.module.css'

export function SpacesNavigation({onLinkClick}: {onLinkClick: () => void}) {
  const {customCopilotId, customCopilots} = useChatStateValues('customCopilotId', 'customCopilots')
  useAvailableCustomCopilots()
  const navigate = useNavigate()
  const manager = useChatManager()
  const navigateToNewThread = useNavigateToNewThread()

  const isSpaceList = isCopilotSpacesListPath()

  const handleCopilotSpaceDelete = useCallback(
    async (item: CustomCopilot) => {
      const spaceToDelete = customCopilots?.find(copilot => copilot.id === item.id)
      if (spaceToDelete) {
        // navigate away before deleting
        if (item.id === customCopilotId) navigate(COPILOT_PATH)
        await manager.deleteCopilotSpace(spaceToDelete)
      }
    },
    [customCopilots, customCopilotId, navigate, manager],
  )

  const handleCopilotSpaceClick = async (item: CustomCopilot) => {
    const selectedCustomCopilotId = item.id
    await navigateToNewThread({
      clearTopic: true,
      includeThreads: false,
      customCopilotId: selectedCustomCopilotId,
    })

    onLinkClick()

    manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: selectedCustomCopilotId})
    sendEvent('dotcom_chat.activate', {
      target: 'SIDEBAR_CUSTOM_COPILOT_SELECTED',
      mode: 'immersive',
    })
  }

  return (
    <Navigation
      aria-current={isSpaceList ? 'page' : undefined}
      contextMenuComponent={
        <IconButton
          as="a"
          aria-label="Create Space"
          href={CREATE_CUSTOM_COPILOTS_URL}
          icon={PlusIcon}
          variant="invisible"
        />
      }
      displayName="Spaces"
      expandOnClick={false}
      hasItems={!!customCopilots?.length}
      href={COPILOT_SPACES_PATH}
      iconOverride={<SpacesIcon size={16} />}
      id="spaces"
    >
      {customCopilots?.map(item => (
        <NavigationSubItem
          key={item.id}
          aria-current={item.id === customCopilotId && !isSpaceList ? 'page' : undefined}
          contextMenuComponent={<CopilotSpacesMenu copilot={item} onDelete={() => handleCopilotSpaceDelete(item)} />}
          displayName={item.name}
          href={getCopilotSpacePath(item.id)}
          iconOverride={<GitHubAvatar className={styles.avatar} size={16} src={item.primaryAvatarPath} />}
          onLinkClick={() => handleCopilotSpaceClick(item)}
        />
      ))}
    </Navigation>
  )
}
