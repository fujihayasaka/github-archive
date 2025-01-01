import {Heading, Popover, Spinner} from '@primer/react'

import styles from './paginated-archive-mutation-in-progress-dialog.module.css'

type Props = {
  headerText: string
}

export const PaginatedArchiveMutationInProgressDialog = ({headerText}: Props) => {
  return (
    <Popover open caret="bottom" className={styles.Popover}>
      <Popover.Content className={styles.Popover_Content}>
        <Heading as="h2" className={styles.Heading}>
          {headerText}
        </Heading>
        <div className={styles.Box}>
          <Spinner />
          <span className={styles.Text}>This may take some time. This dialog will close when the job is complete.</span>
        </div>
      </Popover.Content>
    </Popover>
  )
}
