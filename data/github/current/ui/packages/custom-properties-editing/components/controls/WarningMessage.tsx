import {AlertIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

import styles from './WarningMessage.module.css'

export function WarningMessage({children}: PropsWithChildren) {
  return (
    <div
      className={clsx(
        styles.messageContainer,
        'd-flex gap-2 text-small color-fg-attention color-bg-attention border-top border-bottom color-border-attention',
      )}
    >
      <AlertIcon size={16} />
      <div>{children}</div>
    </div>
  )
}
