import {Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {AlertIcon} from '@primer/octicons-react'

import styles from './BranchNextStepFlashes.module.css'

export type BranchNextStepFlashesProps = {
  errorMessages: string[]
}

export const BranchNextStepFlashes = ({errorMessages}: BranchNextStepFlashesProps) => {
  if (errorMessages.length === 0) {
    return null
  }

  return (
    <div className={styles.box}>
      {errorMessages.map((errorMessage, index) => (
        <Flash key={`${errorMessage}-${String(index)}`} variant="warning">
          <Octicon icon={AlertIcon} />
          <span>{errorMessage}</span>
        </Flash>
      ))}
    </div>
  )
}
