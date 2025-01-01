import {sendEvent} from '@github-ui/hydro-analytics'
import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import styles from './ChatPagingComponent.module.css'

type ChatPagingComponentProps = {
  currentPage: number
  totalPages: number
  onPrev: (page: number) => void
  onNext: (page: number) => void
  isUserMessage: boolean
  disabled?: boolean
}

export function ChatPagingComponent({
  currentPage,
  totalPages,
  onPrev,
  onNext,
  isUserMessage,
  disabled = false,
}: ChatPagingComponentProps) {
  if (currentPage < 1) {
    throw new Error('currentPage must be greater than or equal to 1')
  }
  if (totalPages < 1) {
    throw new Error('totalPages must be greater than or equal to 1')
  }
  if (currentPage > totalPages) {
    throw new Error('currentPage must be less than or equal to totalPages')
  }

  const isFirstOfSiblings = currentPage === 1
  const isLastOfSiblings = currentPage === totalPages
  const previousButtonStyle = isFirstOfSiblings ? styles.disabledButton : ''
  const nextButtonStyle = isLastOfSiblings ? styles.disabledButton : ''

  const handlePrevClick = () => {
    const eventTarget = isUserMessage ? 'USER_MESSAGE_ACTION_PREVIOUS_RESPONSE' : 'RESPONSE_ACTION_PREVIOUS_RESPONSE'
    sendEvent('dotcom_chat.activate', {target: eventTarget, mode: 'immersive'})
    onPrev(currentPage - 1)
  }

  const handleNextClick = () => {
    const eventTarget = isUserMessage ? 'USER_MESSAGE_ACTION_NEXT_RESPONSE' : 'RESPONSE_ACTION_NEXT_RESPONSE'
    sendEvent('dotcom_chat.activate', {target: eventTarget, mode: 'immersive'})
    onNext(currentPage + 1)
  }

  return (
    <div className={styles.container} data-testid="chat-paging-component">
      <IconButton
        variant="invisible"
        aria-label="Previous Response"
        onClick={handlePrevClick}
        icon={ChevronLeftIcon}
        disabled={isFirstOfSiblings || disabled}
        className={previousButtonStyle}
      />

      <span className={styles.pageIndicator}>
        {currentPage}/{totalPages}
      </span>

      <IconButton
        variant="invisible"
        aria-label="Next Response"
        onClick={handleNextClick}
        icon={ChevronRightIcon}
        disabled={isLastOfSiblings || disabled}
        className={nextButtonStyle}
      />
    </div>
  )
}
