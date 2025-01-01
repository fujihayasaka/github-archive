import {CanIndexStatus} from '@github-ui/copilot-chat/utils/copilot-chat-hooks'
import {AlertIcon, StopIcon} from '@primer/octicons-react'
import {Dialog} from '@primer/react'
import type {RefObject} from 'react'

import styles from './IndexingUnavailableDialog.module.css'

type CannotIndexStatus = Exclude<CanIndexStatus, CanIndexStatus.CanIndex>

interface IndexingUnavailableDialogProps {
  onClose: () => void
  status: CannotIndexStatus
  hitIndividualLimit: boolean
  returnFocusRef: RefObject<HTMLElement>
}

const errorMessage = (status: CannotIndexStatus, hitIndividualLimit: boolean) => {
  switch (status) {
    case CanIndexStatus.QuotaExhausted:
      return hitIndividualLimit
        ? {
            title: 'You have reached your semantic search token limit',
            description: 'Please wait for more tokens to be granted',
            Icon: AlertIcon,
            iconColor: 'var(--fgColor-attention)',
          }
        : {
            title: 'Your organization has reached its limit for semantic search indexing',
            description: 'Please wait for more tokens to be granted',
            Icon: AlertIcon,
            iconColor: 'var(--fgColor-attention)',
          }
    case CanIndexStatus.Forbidden:
      return {
        title: 'You may only index repositories that your organization owns',
        iconColor: 'var(--fgColor-attention)',
        Icon: AlertIcon,
        description: 'Switch to a different repository you own to start indexing',
      }
    case CanIndexStatus.ServiceUnavailable:
      return {
        title: 'Indexing temporarily unavailable due to heavy load',
        description: 'Try again later',
        iconColor: 'var(--fgColor-danger)',
        Icon: StopIcon,
      }
    default:
      return {
        title: 'Indexing temporarily unavailable',
        description: 'Try again later',
        Icon: AlertIcon,
        iconColor: 'var(--fgColor-attention)',
      }
  }
}

export function IndexingUnavailableDialog({
  onClose,
  status,
  hitIndividualLimit,
  returnFocusRef,
}: IndexingUnavailableDialogProps) {
  const {title, description, Icon, iconColor} = errorMessage(status, hitIndividualLimit)

  return (
    <Dialog
      width="large"
      title="Unable to index"
      position={{
        narrow: 'fullscreen',
        regular: 'center',
      }}
      onClose={onClose}
      returnFocusRef={returnFocusRef}
    >
      <div className={styles.body}>
        <div style={{color: iconColor}}>
          <Icon size={24} />
        </div>
        <div className={styles.message}>
          <h2 className={styles.title}>{title}</h2>
          <p className={styles.description}>{description}</p>
        </div>
      </div>
    </Dialog>
  )
}
