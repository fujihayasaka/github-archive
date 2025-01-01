import {Dialog} from '@primer/react/experimental'
import {CopyIcon} from '@primer/octicons-react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'

import styles from './BranchNextStepLocal.module.css'

export type BranchNextStepLocalProps = {
  branch: string | null
  onClose: () => void
  flashes?: React.ReactNode
}

export const BranchNextStepLocal = ({branch, onClose, flashes}: BranchNextStepLocalProps) => {
  const content = `git fetch origin
git checkout ${branch}`

  return (
    <Dialog width="large" height="auto" title="Checkout in your local repository" onClose={onClose}>
      {flashes}
      <span className={styles.infoText}>Run the following commands in your local clone.</span>
      <div className={styles.box}>
        <span className={styles.copyText}>{content}</span>
        <CopyToClipboardButton
          textToCopy={content}
          ariaLabel="Copy to clipboard"
          icon={CopyIcon}
          tooltipProps={{direction: 'w'}}
        />
      </div>
    </Dialog>
  )
}
