import {clsx} from 'clsx'
import type React from 'react'
import styles from './OutputCell.module.css'

import {BranchName} from '@primer/react'

export const CellResultPill = ({children}: {children: React.ReactNode}) => {
  return (
    <BranchName as="span" role="cell" className={clsx(styles.cellResults, 'mb-1 mr-1 color-fg-muted text-small')}>
      {children}
    </BranchName>
  )
}
