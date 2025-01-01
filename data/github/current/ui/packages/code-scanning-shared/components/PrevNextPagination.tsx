import {useCallback} from 'react'
import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import type {Cursor} from '../types/cursor'
import {clsx} from 'clsx'
import styles from './PrevNextPagination.module.css'

export interface PrevNextPaginationProps {
  prevCursor: string | undefined
  nextCursor: string | undefined
  onCursorChange: (newCursor: Cursor) => void
}

export function PrevNextPagination({prevCursor, nextCursor, onCursorChange}: PrevNextPaginationProps) {
  const previousButtonDisabled = !prevCursor
  const nextButtonDisabled = !nextCursor

  const handlePreviousButtonClick = useCallback(() => {
    if (!prevCursor) {
      return
    }

    onCursorChange({
      before: prevCursor,
    })
  }, [onCursorChange, prevCursor])
  const handleNextButtonClick = useCallback(() => {
    if (!nextCursor) {
      return
    }

    onCursorChange({
      after: nextCursor,
    })
  }, [onCursorChange, nextCursor])

  // If both buttons are disabled, we don't show the pagination
  if (previousButtonDisabled && nextButtonDisabled) {
    return null
  }

  return (
    <div className={clsx('d-flex flex-justify-center', styles.container)}>
      <Button
        variant="invisible"
        className={clsx(previousButtonDisabled ? '' : 'fgColor-accent')}
        disabled={previousButtonDisabled}
        leadingVisual={ChevronLeftIcon}
        onClick={handlePreviousButtonClick}
        data-testid="previous-button"
      >
        Previous
      </Button>
      <Button
        variant="invisible"
        className={clsx(nextButtonDisabled ? '' : 'fgColor-accent')}
        disabled={nextButtonDisabled}
        trailingVisual={ChevronRightIcon}
        onClick={handleNextButtonClick}
        data-testid="next-button"
      >
        Next
      </Button>
    </div>
  )
}
