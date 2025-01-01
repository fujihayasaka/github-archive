import {Spinner} from '@primer/react'
import {Dialog} from '@primer/react/experimental'

import ChecksStatusBadgeFooter from './components/ChecksStatusBadgeFooter'
import HeaderState from './components/ChecksStatusBadgeHeader'
import type {CombinedStatusResult} from './index'

import styles from './CheckStatusDialog.module.css'

interface CheckStatusDialogProps {
  combinedStatus?: CombinedStatusResult
  isOpen: boolean
  onDismiss: () => void
}

export function CheckStatusDialog(props: CheckStatusDialogProps) {
  const {combinedStatus, isOpen, onDismiss} = props

  const title = combinedStatus ? <HeaderState checksHeaderState={combinedStatus.checksHeaderState} /> : 'Loading...'

  return isOpen ? (
    <Dialog
      onClose={onDismiss}
      title={title}
      subtitle={combinedStatus ? combinedStatus.checksStatusSummary : undefined}
      width="xlarge"
      renderBody={() => (
        <Dialog.Body className={styles.Dialog_Body}>
          {combinedStatus ? (
            <ChecksStatusBadgeFooter checkRuns={combinedStatus.checkRuns} />
          ) : (
            <div className={styles.Box}>
              <Spinner size="medium" />
            </div>
          )}
        </Dialog.Body>
      )}
      className={styles.Dialog}
    />
  ) : null
}
