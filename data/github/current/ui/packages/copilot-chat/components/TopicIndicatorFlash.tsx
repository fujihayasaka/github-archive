import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import type {RefObject} from 'react'

import {isFileReference, isRepository, isSnippetReference} from '../utils/copilot-chat-helpers'
import type {CopilotChatReference, CopilotChatRepo, Docset} from '../utils/copilot-chat-types'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './TopicIndicatorFlash.module.css'

export interface TopicIndicatorFlashProps {
  icon: React.ReactNode
  topic: CopilotChatRepo | Docset
  /** Only shown on large screens. */
  additionalNonMobileActions?: React.ReactNode
  /** Only shown on small screens. */
  mobileActions?: React.ReactNode
  removeButtonRef?: RefObject<HTMLButtonElement>
}

export function TopicIndicatorFlash({
  icon,
  topic,
  additionalNonMobileActions,
  mobileActions,
  removeButtonRef,
}: TopicIndicatorFlashProps) {
  const manager = useChatManager()
  const {mode, currentReferences, selectedThreadID} = useChatState()
  const isImmersive = mode === 'immersive'
  const name = isRepository(topic) ? `${topic.ownerLogin}/${topic.name}` : topic.name

  const detachTopic = () => {
    copilotLocalStorage.setSelectedTopic(selectedThreadID ?? '', null)
    copilotLocalStorage.setCurrentReferences(selectedThreadID ?? '', [])
    manager.clearCurrentTopic()
    manager.clearCurrentReferences(['image', 'issue'])

    // remove references to files in this repo
    const removedReferences = [] as CopilotChatReference[]
    for (const reference of currentReferences) {
      if (topic && (isFileReference(reference) || isSnippetReference(reference)) && reference.repoID === topic.id) {
        removedReferences.push(reference)
      }
    }
    manager.removeReferences(removedReferences)
  }

  return (
    <div className={clsx(styles.container, {[styles.containerAssistive]: !isImmersive})}>
      <span className={styles.icon}>{icon}</span>
      <span>{name}</span>
      <span style={{flex: 1}} />
      <div className={clsx(styles.nonMobileOnly, styles.status)}>
        {additionalNonMobileActions !== undefined && <>{additionalNonMobileActions}</>}
      </div>
      {mobileActions !== undefined && <div className={styles.mobileOnly}>{mobileActions}</div>}
      <IconButton
        icon={XIcon}
        variant="invisible"
        size="small"
        aria-label="Remove topic"
        onClick={detachTopic}
        className={clsx(styles.removeButton, {[styles.assistive]: mode === 'assistive'})}
        ref={removeButtonRef}
      />
    </div>
  )
}
