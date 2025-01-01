import {type CSSProperties, useCallback} from 'react'
import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'

interface Props {
  prevCursor: string | undefined
  nextCursor: string | undefined
  onCursorChange: (newCursor: Cursor) => void
}

type Cursor =
  | {
      before: string
    }
  | {
      after: string
    }

export function PrevNextPagination({prevCursor, nextCursor, onCursorChange}: Props): JSX.Element {
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
      >
        Previous
      </Button>
      <Button
        variant="invisible"
        sx={{color: nextButtonDisabled ? undefined : 'accent.fg'}}
        disabled={nextButtonDisabled}
        trailingVisual={ChevronRightIcon}
        onClick={handleNextButtonClick}
      >
        Next
      </Button>
    </Box>
  )
}
