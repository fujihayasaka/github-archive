import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {clsx} from 'clsx'

import styles from './CursorPagination.module.css'

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
    <div className={clsx('d-flex flex-justify-center', styles.Box)}>
      <Button
        variant="invisible"
        className={prevBtnColor}
        disabled={prevBtnDisabled}
        leadingVisual={() => <ChevronLeftIcon className={prevIconColor} />}
        onClick={() => onPageChange(previousCursor)}
      >
        <span className={styles.Text}>Previous</span>
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
    </div>
  )
}
