import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Box, Button, Text} from '@primer/react'

interface Props {
  previousCursor?: string
  nextCursor?: string
  onPageChange: (newCursor?: string) => void
}

export function CursorPagination({previousCursor, nextCursor, onPageChange}: Props): JSX.Element {
  const prevBtnDisabled = !previousCursor
  const nextBtnDisabled = !nextCursor

  const prevBtnColor = prevBtnDisabled ? '' : 'fgColor-accent'
  const nextBtnColor = nextBtnDisabled ? '' : 'fgColor-accent'
  const prevIconColor = prevBtnDisabled ? 'fgColor-muted' : 'fgColor-accent'
  const nextIconColor = nextBtnDisabled ? 'fgColor-muted' : 'fgColor-accent'

  return (
    <Box className="d-flex flex-justify-center" sx={{gap: 1}}>
      <Button
        variant="invisible"
        className={prevBtnColor}
        disabled={prevBtnDisabled}
        leadingVisual={() => <ChevronLeftIcon className={prevIconColor} />}
        onClick={() => onPageChange(previousCursor)}
      >
        <Text sx={{ml: 2}}>Previous</Text>
      </Button>
      <Button
        variant="invisible"
        className={nextBtnColor}
        disabled={nextBtnDisabled}
        trailingVisual={() => <ChevronRightIcon className={nextIconColor} />}
        onClick={() => onPageChange(nextCursor)}
      >
        Next
      </Button>
    </Box>
  )
}
