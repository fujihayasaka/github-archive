import {Flash} from '@primer/react'
import {memo} from 'react'

import styles from './ErrorMessage.module.css'

export const ErrorMessage = memo(({message}: {message: string}) => (
  <Flash variant="danger" full className={styles.flash}>
    {message}
  </Flash>
))
ErrorMessage.displayName = 'MarkdownEditor.ErrorMessage'
