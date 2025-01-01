import {SyncIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import {useEntitlement} from '../components/quota/EntitlementContext'
import type {CopilotChatModel} from '../utils/copilot-chat-types'
import {ModelPicker} from './ModelPicker'

export interface RetryButtonProps {
  handleRetryMessage: (model?: CopilotChatModel) => void
  disabled?: boolean
  showModelPicker?: boolean
  model?: CopilotChatModel
  navigateToNewThread?: () => Promise<void>
}

export function RetryButton({
  handleRetryMessage,
  disabled = false,
  showModelPicker = false,
  model,
  navigateToNewThread,
}: RetryButtonProps) {
  const handleClick = () => {
    handleRetryMessage(model)
  }

  const {isLicensedLimited} = useEntitlement()

  if (showModelPicker && (!navigateToNewThread || !model)) {
    throw new Error('navigateToNewThread and model must be provided in order to show the model picker')
  }

  return showModelPicker ? (
    <ModelPicker
      onNewThreadSelected={navigateToNewThread!}
      limited={isLicensedLimited}
      type={'message-retry'}
      selectedModel={model}
      onModelSelected={handleRetryMessage}
      disabled={disabled}
    />
  ) : (
    <IconButton
      variant="invisible"
      aria-label="Retry"
      data-testid="retry-button"
      onClick={handleClick}
      icon={SyncIcon}
      disabled={disabled}
    />
  )
}
