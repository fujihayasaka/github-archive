import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import styles from './SuggestionPaginator.module.css'

export const SuggestionPaginator = ({
  currentIndex,
  pageCount,
  onClick,
}: {
  currentIndex: number
  pageCount: number
  onClick: (newPage: number) => void
}) => {
  const currentPage = currentIndex + 1

  if (pageCount < 2 || currentPage < 1) {
    return null
  }
  return (
    <div className={styles.paginatorContainer}>
      <IconButton
        aria-label="Previous suggestion"
        icon={ChevronLeftIcon}
        variant="invisible"
        tooltipDirection="n"
        onClick={() => onClick(-1)}
      />
      <span className={styles.paginationNumbers}>
        {currentPage} / {pageCount}
      </span>
      <IconButton
        aria-label="Next suggestion"
        icon={ChevronRightIcon}
        variant="invisible"
        tooltipDirection="n"
        onClick={() => onClick(1)}
      />
    </div>
  )
}
