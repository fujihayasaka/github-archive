import {ChevronLeftIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import styles from './paginated-archive-footer.module.css'

function ArchiveFooterWrapper({children}: {children: React.ReactNode}) {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>{children}</div>
    </div>
  )
}

type PaginatedArchiveFooterProps = {
  onFetchNextPage?: () => void
  onFetchPreviousPage?: () => void
  hasResults: boolean
  mutationIsLoading: boolean
}

export function PaginatedArchiveFooter({
  hasResults,
  onFetchNextPage,
  onFetchPreviousPage,
  mutationIsLoading,
}: PaginatedArchiveFooterProps) {
  if (!hasResults) return null

  const hasPreviousPage = onFetchPreviousPage && !mutationIsLoading
  const hasNextPage = onFetchNextPage && !mutationIsLoading

  return (
    <ArchiveFooterWrapper>
      <div className={styles.Box_2}>
        <div className={styles.Box_3}>
          <Button disabled={!hasPreviousPage} onClick={onFetchPreviousPage}>
            {hasPreviousPage && <Octicon icon={ChevronLeftIcon} />} Previous
          </Button>
          <Button disabled={!hasNextPage} onClick={onFetchNextPage}>
            Next {hasNextPage && <Octicon icon={ChevronRightIcon} />}
          </Button>
        </div>
      </div>
    </ArchiveFooterWrapper>
  )
}
