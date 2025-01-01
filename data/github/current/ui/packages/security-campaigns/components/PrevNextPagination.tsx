import {type CSSProperties, useCallback} from 'react'
import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import type {Cursor} from '../types/cursor'

interface Props {
  prevCursor: string | undefined
  nextCursor: string | undefined
  onCursorChange: (newCursor: Cursor) => void
}

export function PrevNextPagination({prevCursor, nextCursor, onCursorChange}: Props) {
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
    <Box
      sx={{display: 'flex', justifyContent: 'center', gap: 1}}
      style={{'--button-invisible-bgColor-disabled': 'transparent'} as CSSProperties}
    >
      <Button
        variant="invisible"
        sx={{color: previousButtonDisabled ? undefined : 'accent.fg'}}
        disabled={previousButtonDisabled}
        leadingVisual={ChevronLeftIcon}
        onClick={handlePreviousButtonClick}
        data-testid="previous-button"
      >
        Previous
      </Button>
      <Button
        variant="invisible"
        sx={{color: nextButtonDisabled ? undefined : 'accent.fg'}}
        disabled={nextButtonDisabled}
        trailingVisual={ChevronRightIcon}
        onClick={handleNextButtonClick}
        data-testid="next-button"
      >
        Next
      </Button>
    </Box>
  )
}
