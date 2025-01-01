import {RepoIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {clsx} from 'clsx'

import {isRepository} from '../utils/copilot-chat-helpers'
import {TopicIndexStatus, useRepoIndexingState} from '../utils/copilot-chat-hooks'
import type {CopilotChatRepo} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './TopicIndicator.module.css'

export function TopicIndicator() {
  const {currentTopic, repoCustomInstructionsEnabled} = useChatState()
  const repo = isRepository(currentTopic) ? currentTopic : undefined

  if (!repo) return null

  // NOTE: currently we are using this indicator for custom instructions
  //       but we will likely use it for other things in the future.
  if (!repo.customInstructions) return null

  return <RepoIndicator repo={repo} instructionsEnabled={repoCustomInstructionsEnabled} />
}

interface Props {
  repo: CopilotChatRepo
  instructionsEnabled: boolean
}

function RepoIndicator({repo, instructionsEnabled}: Props) {
  const manager = useChatManager()

  const nameWithOwner = `${repo.ownerLogin}/${repo.name}`
  const [indexingState] = useRepoIndexingState(nameWithOwner)

  const isIndexed = indexingState.code === TopicIndexStatus.Indexed

  return (
    <div className={clsx(styles.container, isIndexed && styles.containerIsIndexed)}>
      <span className={styles.icon}>
        <RepoIcon />
      </span>
      <span>{nameWithOwner}</span>
      <span style={{flex: 1}} />
      <div className={styles.status}>
        <Tooltip text="Instructions provide context to inform responses">
          <span className={styles.customInstructionsStatus}>
            <Link
              className={styles.customInstructionsCTA}
              as="button"
              muted
              inline
              data-testid="trigger-button"
              onClick={() => manager.toggleRepoCustomInstructions(!instructionsEnabled)}
            >
              {instructionsEnabled ? 'Disable instructions' : 'Enable instructions'}
            </Link>
          </span>
        </Tooltip>
      </div>
    </div>
  )
}
